import AppKit
// @preconcurrency: SwiftTerm 1.13.0 has no Swift 6 Sendable annotations.
// LocalProcess defaults its dispatch queue to DispatchQueue.main, so delegate
// callbacks arrive on the main thread — the @MainActor Coordinator below is safe.
@preconcurrency import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: View {
    let session: TerminalClaudeSession
    // False while the inspector is closed or another tab is selected — gates
    // the cursor keep-alive timer + key monitor (the view stays mounted).
    var isVisible: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // .id(restartEpoch) dismantles + remakes the bridge on restart(), respawning
            // the PTY claude — .inspector hides without unmounting, so state alone can't
            // remount. pendingCount/state read in body so updateNSView re-fires on enqueue().
            SwiftTermBridge(
                session: session,
                pendingCount: session.pendingInput.count,
                isRunning: isRunning,
                isVisible: isVisible
            )
            .id(session.restartEpoch)

            if showsBootOverlay {
                bootOverlay
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showsBootOverlay)
    }

    private var showsBootOverlay: Bool {
        if case .starting = session.state { return true }
        return false
    }

    private var isRunning: Bool {
        if case .running = session.state { return true }
        return false
    }

    @ViewBuilder
    private var bootOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Resuming session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Solid hierarchical fill, not .regularMaterial: the overlay sits
        // inside the glass inspector panel and a material would stack a
        // second blur on the glass (ExitBanner discipline next door).
        .background(.quaternary)
    }
}

private struct SwiftTermBridge: NSViewRepresentable {
    let session: TerminalClaudeSession
    // pendingCount + isRunning are dummy parameters in SwiftUI's Equatable diff
    // so updateNSView re-fires when the inject queue grows or the session flips
    // to .running; updateNSView reads session.pendingInput directly for the flush.
    let pendingCount: Int
    let isRunning: Bool
    let isVisible: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> PersistentCursorTerminalView {
        let view = PersistentCursorTerminalView(frame: .zero)
        // Before insertion: a hidden tab's mount must not start the
        // keep-alive in viewDidMoveToWindow.
        view.chromeActive = isVisible
        view.processDelegate = context.coordinator
        // Finder file-drop routes through enqueue (not a direct send) so the
        // .running gate + updateNSView flush handles a drop landing while claude
        // is still booting — it waits in pendingInput until the REPL is ready.
        view.onFilePathsDropped = { [weak session] text in
            session?.enqueue(text)
        }
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // optionAsMetaKey=false lets macOS compose Option sequences (Option+E → €,
        // dead keys); the default sends ESC+letter, losing composition on a German
        // keyboard. Trade-off: Option word-nav is lost, but claude's REPL doesn't use it.
        view.optionAsMetaKey = false
        view.nativeBackgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        applyForeground(to: view)
        applyPalette(to: view)
        context.coordinator.lastColorScheme = colorScheme

        view.caretViewTracksFocus = false
        view.caretColor = NSColor.labelColor
        view.cursorStyleChanged(source: view.terminal, newStyle: .blinkBlock)

        // Bridge owns the attach lifecycle: mounters leave attach() to us so state
        // is guaranteed .starting once a PTY exists. attach() is idempotent on
        // .starting/.running and recovers from .exited (restart()/scenePhase path).
        session.attach()
        // Defense in depth: the null/newline precondition lives in
        // shellQuotedAttachArgs — bail early to avoid spawning into a corrupt
        // environment; mark exited so the ExitBanner surfaces, not a silent empty terminal.
        guard TerminalClaudeSession.isShellSafe(session.cwd.path),
            TerminalClaudeSession.isShellSafe(session.binaryURL.path)
        else {
            session.markExited(code: -1)
            return view
        }
        let args = session.shellSpawnArgs(appearanceIsDark: colorScheme == .dark)
        // Env construction lives in CCI — the PATH points at claude-internal
        // install locations (enforced by the boundary test).
        let env = TerminalClaudeSession.spawnEnvironment()

        view.startProcess(
            executable: "/bin/sh",
            args: args,
            environment: env
        )
        // Synchronous kill path for window-close: stop() fires this before
        // flipping state, so the subprocess dies before SwiftUI gets around
        // to dismantling the view.
        session.registerStopHandler { [weak view] in
            view?.terminate()
        }
        // startProcess returns the instant the PTY is wired up, but claude spends
        // ~1.6s on hooks / plugins / --resume replay. Holding .starting masks that
        // window with the "Resuming session…" overlay until we flip to .running.
        context.coordinator.markStartedTask?.cancel()
        context.coordinator.markStartedTask = Task { @MainActor [weak session] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let session else { return }
            session.markStarted()
        }
        // SwiftTerm starts unfocused inside an NSViewRepresentable; without a
        // firstResponder hand-off the caret renders hollow and keystrokes can drop.
        // Window may still be nil during first layout — best-effort, not load-bearing.
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: PersistentCursorTerminalView, context: Context) {
        nsView.chromeActive = isVisible
        // SwiftTerm focuses only in makeNSView; on a tab switch (isVisible
        // false→true) re-grab focus, but never for a dead exited-session view.
        if isVisible, !context.coordinator.wasVisible, !isExited {
            nsView.window?.makeFirstResponder(nsView)
        }
        context.coordinator.wasVisible = isVisible
        if context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastColorScheme = colorScheme
            nsView.nativeBackgroundColor = .clear
            nsView.layer?.backgroundColor = NSColor.clear.cgColor
            applyForeground(to: nsView)
            applyPalette(to: nsView)
        }
        flushPendingInput(into: nsView)
    }

    private func flushPendingInput(into nsView: PersistentCursorTerminalView) {
        // Gate on .running — the boot overlay covers the terminal until claude
        // has finished its --resume replay; injecting during .starting would
        // land before the prompt is ready and confuse the REPL.
        guard isRunning, !session.pendingInput.isEmpty else { return }
        for text in session.consumePending() {
            nsView.send(txt: text)
        }
    }

    @MainActor
    static func dismantleNSView(
        _ nsView: PersistentCursorTerminalView, coordinator: Coordinator
    ) {
        // Without explicit terminate(), LocalProcess.deinit leaves the child
        // running and the PTY fd pair leaked for the app session.
        coordinator.markStartedTask?.cancel()
        coordinator.markStartedTask = nil
        // Drop the stop-hook before terminate() so a stop() during teardown
        // doesn't end up calling terminate() on a half-disposed view.
        coordinator.session?.clearStopHandler()
        // Tear down AppKit resources on MainActor so PersistentCursorTerminalView's
        // nonisolated deinit (would otherwise touch NSEvent.removeMonitor /
        // Timer.invalidate from arbitrary threads) finds both properties nil and no-ops.
        nsView.stopCursorKeepAlive()
        nsView.removeShiftEnterMonitor()
        nsView.removeMouseFocusMonitor()
        nsView.terminate()
    }

    private var isExited: Bool {
        if case .exited = session.state { return true }
        return false
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    private func applyForeground(to view: PersistentCursorTerminalView) {
        view.nativeForegroundColor =
            colorScheme == .dark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.15, alpha: 1)
    }

    private func applyPalette(to view: PersistentCursorTerminalView) {
        // Index 8 (bright-black / SGR 90) is claude's plan-mode prompt text; the
        // default RGB(129,131,131) is too faint on a light background — override to
        // a mid-dark gray. UInt16 color values are 0–65535 (8-bit value × 257).
        func color(_ red: Int, _ green: Int, _ blue: Int) -> SwiftTerm.Color {
            SwiftTerm.Color(
                red: UInt16(red * 257), green: UInt16(green * 257), blue: UInt16(blue * 257)
            )
        }
        let brightBlack = colorScheme == .light ? color(80, 80, 80) : color(129, 131, 131)
        let palette: [SwiftTerm.Color] = [
            color(0, 0, 0),  // 0  black
            color(194, 54, 33),  // 1  red
            color(37, 188, 36),  // 2  green
            color(173, 173, 39),  // 3  yellow
            color(73, 46, 225),  // 4  blue
            color(211, 56, 211),  // 5  magenta
            color(51, 187, 200),  // 6  cyan
            color(203, 204, 205),  // 7  white
            brightBlack,  // 8  bright black
            color(252, 57, 31),  // 9  bright red
            color(49, 231, 34),  // 10 bright green
            color(234, 236, 35),  // 11 bright yellow
            color(88, 51, 255),  // 12 bright blue
            color(249, 53, 248),  // 13 bright magenta
            color(20, 240, 240),  // 14 bright cyan
            color(233, 235, 235),  // 15 bright white
        ]
        view.installColors(palette)
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var session: TerminalClaudeSession?
        var lastColorScheme: ColorScheme?
        var markStartedTask: Task<Void, Never>?
        var wasVisible = false

        init(session: TerminalClaudeSession) {
            self.session = session
            super.init()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            session?.markExited(code: exitCode ?? 0)
        }
    }
}

// claude's REPL sends DECRST 25 (hide cursor) constantly. Overriding hideCursor
// isn't enough — SwiftTerm's internal Terminal.cursorHidden is unreachable, but
// feeding `\e[?25h` flips it back; a 120 ms repeater wins the race against the hides.
final class PersistentCursorTerminalView: LocalProcessTerminalView {
    // nonisolated(unsafe): Timer? is touched from a MainActor start/stop pair and
    // a nonisolated deinit fallback (the host may short-circuit teardown). Swift 6
    // rejects a MainActor deinit reading isolated state, hence the unsafe storage.
    nonisolated(unsafe) private var cursorKeepAlive: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Timer is started lazily once the view actually enters a window
        // (see viewDidMoveToWindow). Starting in init() ran the 20Hz timer
        // even when the terminal mode wasn't visible.
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // Fallback when dismantleNSView was skipped (normal teardown nils both on
        // MainActor, making this a no-op). Timer.invalidate / NSEvent.removeMonitor
        // are main-thread APIs and deinit can run off-main — ferry onto the main queue.
        guard cursorKeepAlive != nil || shiftEnterMonitor != nil || mouseFocusMonitor != nil
        else { return }
        // @unchecked Sendable: only carries the main-thread-bound references
        // across the queue hop; nothing reads them concurrently.
        struct Teardown: @unchecked Sendable {
            let timer: Timer?
            let tokens: [Any]
        }
        let teardown = Teardown(
            timer: cursorKeepAlive,
            tokens: [shiftEnterMonitor, mouseFocusMonitor].compactMap { $0 }
        )
        cursorKeepAlive = nil
        shiftEnterMonitor = nil
        mouseFocusMonitor = nil
        if Thread.isMainThread {
            teardown.timer?.invalidate()
            teardown.tokens.forEach { NSEvent.removeMonitor($0) }
        } else {
            DispatchQueue.main.async {
                teardown.timer?.invalidate()
                teardown.tokens.forEach { NSEvent.removeMonitor($0) }
            }
        }
    }

    // SwiftTerm's intrinsicContentSize/fittingSize oscillate the layout on
    // inspector-divider drag; noIntrinsicMetric + fittingSize .zero kill both
    // feedback channels. Safe only inside SwiftTermBridge — a raw NSStackView/NSScrollView would collapse to 0pt.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize { .zero }

    // Visibility gate for the keep-alive timer + key monitor: the inspector hides
    // its column instead of unmounting, and hidden tabs stay ZStack-mounted —
    // without this every terminal kept its timer burning behind a closed inspector.
    var chromeActive = true {
        didSet {
            guard chromeActive != oldValue else { return }
            refreshChrome()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            refreshChrome()
            // SwiftTerm registers no dragged types and implements no
            // NSDraggingDestination methods, so this is the
            // sole file-drop handler — no super conflict for .fileURL drags.
            registerForDraggedTypes([.fileURL])
        } else {
            stopCursorKeepAlive()
            removeShiftEnterMonitor()
            removeMouseFocusMonitor()
            unregisterDraggedTypes()
        }
    }

    private func refreshChrome() {
        if window != nil && chromeActive {
            startCursorKeepAlive()
            installShiftEnterMonitor()
            installMouseFocusMonitor()
        } else {
            stopCursorKeepAlive()
            removeShiftEnterMonitor()
            removeMouseFocusMonitor()
        }
    }

    private func startCursorKeepAlive() {
        cursorKeepAlive?.invalidate()
        // .common modes so the timer survives event tracking on the inspector
        // divider; tolerance lets the kernel coalesce ticks. RunLoop.main fires on
        // the main thread, so MainActor.assumeIsolated never traps and saves a Task hop per tick.
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.terminal?.feed(text: "\u{1B}[?25h")
            }
        }
        timer.tolerance = 0.06
        RunLoop.main.add(timer, forMode: .common)
        cursorKeepAlive = timer
    }

    override func hideCursor(source: Terminal) {
        // Intentionally empty — see class comment.
    }

    // SwiftTerm selects on drag without taking first responder, so Cmd+C/V
    // (nil-target menu actions) route to whichever text view holds focus.
    // Click-to-focus like Terminal.app; mouseDown isn't `open`, so a monitor.
    nonisolated(unsafe) private var mouseFocusMonitor: Any?

    private func installMouseFocusMonitor() {
        guard mouseFocusMonitor == nil else { return }
        mouseFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self,
                let window = self.window,
                window === event.window,
                window.firstResponder !== self,
                self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            else { return event }
            window.makeFirstResponder(self)
            return event
        }
    }

    func removeMouseFocusMonitor() {
        if let token = mouseFocusMonitor {
            NSEvent.removeMonitor(token)
            mouseFocusMonitor = nil
        }
    }

    // Explicit targets so NSMenu auto-validation hits SwiftTerm's
    // validateUserInterfaceItem (Copy disabled without a selection) instead
    // of asking the window's first responder.
    override func menu(for event: NSEvent) -> NSMenu? {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "Copy", action: #selector(copy(_:) as (Any) -> Void), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let pasteItem = NSMenuItem(
            title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)
        return menu
    }

    // claude's REPL submits on `\r` and treats `\n` as a soft newline. SwiftTerm
    // submits Return/Numpad Enter even with Shift held, and its keyDown isn't `open` —
    // a local NSEvent monitor (only while firstResponder) intercepts the keystroke first.
    nonisolated(unsafe) private var shiftEnterMonitor: Any?

    private func installShiftEnterMonitor() {
        guard shiftEnterMonitor == nil else { return }
        shiftEnterMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                let window = self.window,
                window === event.window,
                window.firstResponder === self,
                event.modifierFlags.contains(.shift),
                event.keyCode == 36 || event.keyCode == 76
            else { return event }
            self.send(txt: "\n")
            return nil
        }
    }

    func removeShiftEnterMonitor() {
        if let token = shiftEnterMonitor {
            NSEvent.removeMonitor(token)
            shiftEnterMonitor = nil
        }
    }

    // Set by SwiftTermBridge.makeNSView to route a Finder file-drop through
    // TerminalClaudeSession.enqueue. Nil-safe: if unwired we fall back to a
    // direct send so the view stays usable outside the bridge.
    var onFilePathsDropped: ((String) -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(from: sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let text = DroppedFilePaths.insertionText(for: urls)
        guard !text.isEmpty else { return false }
        if let onFilePathsDropped {
            onFilePathsDropped(text)
        } else {
            send(txt: text)
        }
        return true
    }

    private func droppedFileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options)
        return objects as? [URL] ?? []
    }

    // Called from SwiftTerm's existing terminate() when the host removes the
    // view, so we don't need to access Timer from a non-isolated deinit (which
    // Swift 6 rejects).
    func stopCursorKeepAlive() {
        cursorKeepAlive?.invalidate()
        cursorKeepAlive = nil
    }
}
