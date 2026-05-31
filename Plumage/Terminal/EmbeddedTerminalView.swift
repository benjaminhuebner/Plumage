import AppKit
// @preconcurrency: SwiftTerm 1.13.0 (swift-tools 5.9) has no Swift 6 Sendable
// annotations. LocalProcess defaults its dispatch queue to DispatchQueue.main,
// so all LocalProcessTerminalViewDelegate callbacks arrive on the main thread —
// the @MainActor Coordinator below is safe. See notes.md #00021-embedded-terminal.
@preconcurrency import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: View {
    let session: TerminalClaudeSession

    var body: some View {
        ZStack {
            // .id(restartEpoch) forces SwiftUI to dismantle + remake the
            // bridge when restart() bumps the epoch, which respawns the
            // PTY-owned claude subprocess. State changes alone don't remount
            // because the bridge persists across inspector toggles —
            // SwiftUI's .inspector(isPresented:) hides the column rather
            // than removing its content from the view tree.
            //
            // pendingCount/state read in body so @Observable picks them up
            // as deps — without that, SwiftTermBridge.updateNSView wouldn't
            // re-fire on enqueue() and the inject queue would sit unflushed.
            SwiftTermBridge(
                session: session,
                pendingCount: session.pendingInput.count,
                isRunning: isRunning
            )
            .id(session.restartEpoch)

            if showsBootOverlay {
                bootOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsBootOverlay)
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
        .background(.regularMaterial)
    }
}

private struct SwiftTermBridge: NSViewRepresentable {
    let session: TerminalClaudeSession
    // pendingCount + isRunning are dummy parameters that participate in
    // SwiftUI's Equatable diff so updateNSView re-fires when the inject
    // queue grows or when the session flips into .running. updateNSView
    // reads session.pendingInput directly to perform the flush.
    let pendingCount: Int
    let isRunning: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> PersistentCursorTerminalView {
        let view = PersistentCursorTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        // Finder file-drop routes through enqueue (not a direct send) so the
        // existing .running gate + updateNSView flush machinery handles a drop
        // that lands while claude is still booting — the path waits in
        // pendingInput and flushes once the REPL is ready.
        view.onFilePathsDropped = { [weak session] text in
            session?.enqueue(text)
        }
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // optionAsMetaKey=false lets macOS' text-input layer compose Option
        // sequences (Option+E → €, Option+U dead-key, etc.). With the
        // default `true`, SwiftTerm intercepts the option-branch and sends
        // ESC+letter — losing composition on a German keyboard. Trade-off:
        // Option+Left/Right loses Emacs word-nav, but claude's REPL drives
        // its own input layer where that's unused.
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

        // Bridge owns the attach lifecycle: anyone who mounts a session
        // (TerminalTabsModel.addTab, scene-phase recovery, restart()) leaves
        // attach() to us so state is guaranteed to be .starting once a PTY
        // exists. attach() is idempotent on .starting/.running and recovers
        // from .exited (the restart() / scenePhase path).
        session.attach()
        // Defense in depth: TerminalClaudeSession's shellSpawnArgs already
        // single-quote-escapes ', but precondition on null/newline lives in
        // shellQuotedAttachArgs — bail out early to avoid spawning into a
        // corrupt environment. Mark exited so the ExitBanner surfaces instead
        // of leaving a silent empty terminal.
        guard TerminalClaudeSession.isShellSafe(session.cwd.path),
            TerminalClaudeSession.isShellSafe(session.binaryURL.path)
        else {
            session.markExited(code: -1)
            return view
        }
        let args = session.shellSpawnArgs()
        let env = Self.environmentForClaude()

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
        // SwiftTerm's startProcess returns the instant the PTY is wired up,
        // but claude itself spends ~1.6s on hooks / plugins / CLAUDE.md /
        // --resume replay. Holding the session in .starting masks that window
        // with the "Resuming session…" overlay; once we flip to .running the
        // overlay fades. We only re-enter .starting when restart() bumps
        // restartEpoch and SwiftUI re-mounts the bridge.
        context.coordinator.markStartedTask?.cancel()
        context.coordinator.markStartedTask = Task { @MainActor [weak session] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let session else { return }
            session.markStarted()
        }
        // SwiftTerm starts unfocused inside an NSViewRepresentable. Without
        // a firstResponder hand-off the caret renders as a hollow outline
        // (drawCursor uses TerminalView.hasFocus) and keystrokes can be
        // dropped (notes.md 2026-05-12 #00020-spike entry). Window may
        // still be nil during the first layout pass — the responder hop
        // is best-effort, not load-bearing.
        view.window?.makeFirstResponder(view)
        return view
    }

    func updateNSView(_ nsView: PersistentCursorTerminalView, context: Context) {
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
        // Tear down AppKit resources on MainActor here so PersistentCursorTerminalView's
        // deinit (which is nonisolated under Swift 6 and would otherwise touch
        // NSEvent.removeMonitor / Timer.invalidate from arbitrary threads) finds
        // both properties already nil and becomes a no-op.
        nsView.stopCursorKeepAlive()
        nsView.removeShiftEnterMonitor()
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    private func applyForeground(to view: PersistentCursorTerminalView) {
        view.nativeForegroundColor =
            colorScheme == .dark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.15, alpha: 1)
    }

    private func applyPalette(to view: PersistentCursorTerminalView) {
        // Build a 16-color ANSI palette based on SwiftTerm's default
        // terminalAppColors. Index 8 (bright-black / SGR 90) is used by
        // claude's plan-mode prompt text. The default RGB(129,131,131) is
        // too faint on a light background; override to a mid-dark gray that
        // provides adequate contrast. UInt16 color values are 0–65535
        // (8-bit value × 257 = full-range equivalent).
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

    private static func environmentForClaude() -> [String] {
        // Inherit the parent app's full environment so claude finds the same
        // auth state (credentials, env tokens, keychain access) that the
        // chat-mode subprocess gets. The earlier minimal-allowlist approach
        // left interactive claude unauthenticated even though chat mode
        // worked. Override TERM and augment PATH for a launched-from-Finder
        // Plumage that didn't inherit the user's shell PATH.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath =
            env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] =
            "\(basePath):/opt/homebrew/bin:\(home)/.local/bin:\(home)/.claude/local"
        return env.map { "\($0.key)=\($0.value)" }
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var session: TerminalClaudeSession?
        var lastColorScheme: ColorScheme?
        var markStartedTask: Task<Void, Never>?

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

// claude's interactive REPL sends DECRST 25 (hide cursor) constantly while it
// renders its TUI. SwiftTerm's hide handling lives in two places: the
// delegate callback `hideCursor(source:)`, which we override to a no-op, AND
// the internal flag `Terminal.cursorHidden` which `updateCursorPosition` reads
// every render to decide whether to remove caretView from the hierarchy.
// Plumage can't reach `cursorHidden` directly, but feeding `\e[?25h` (DECSET
// 25 = show cursor) into the terminal parses claude-side and flips the flag
// back to false. A 120 ms repeater wins the race against claude's frequent
// hide commands; the cursor stays continuously visible at the input cell.
final class PersistentCursorTerminalView: LocalProcessTerminalView {
    // nonisolated(unsafe): Timer? is touched from a MainActor-bound start/stop
    // pair and from a nonisolated deinit fallback. SwiftTerm's host normally
    // calls dismantleNSView (which invokes stopCursorKeepAlive) before drop,
    // but the deinit guards against the case where the host short-circuits
    // teardown — Swift 6 rejects a MainActor deinit reading isolated state,
    // hence the unsafe storage. See notes.md #00021-embedded-terminal.
    nonisolated(unsafe) private var cursorKeepAlive: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Timer is started lazily once the view actually enters a window
        // (see viewDidMoveToWindow). Starting in init() ran the 20Hz timer
        // even when the terminal mode wasn't visible.
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // Fallback for the abnormal path where dismantleNSView was skipped.
        // Normal teardown nils both properties on MainActor via dismantleNSView,
        // making this a no-op — Timer.invalidate / NSEvent.removeMonitor are
        // not documented as thread-safe and must not run from a nonisolated
        // deinit in the normal path.
        cursorKeepAlive?.invalidate()
        cursorKeepAlive = nil
        if let token = shiftEnterMonitor {
            NSEvent.removeMonitor(token)
            shiftEnterMonitor = nil
        }
    }

    // SwiftTerm's published intrinsicContentSize/fittingSize feed AppKit's
    // Update-Constraints-In-Window pass on inspector-divider drag and
    // oscillate the layout. noIntrinsicMetric tells AppKit we have no
    // preferred size; fittingSize = .zero kills the second feedback channel.
    //
    // Safe only because this view is exclusively hosted inside
    // SwiftTermBridge (an NSViewRepresentable) — SwiftUI sizes the host via
    // its own proposal mechanism and ignores AppKit intrinsic/fitting
    // metrics. Don't drop this view into a raw NSStackView / NSScrollView;
    // those WOULD respect fittingSize and collapse to 0pt.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize { .zero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startCursorKeepAlive()
            installShiftEnterMonitor()
            // SwiftTerm registers no dragged types and implements no
            // NSDraggingDestination methods (notes.md #00020), so this is the
            // sole file-drop handler — no super conflict for .fileURL drags.
            registerForDraggedTypes([.fileURL])
        } else {
            stopCursorKeepAlive()
            removeShiftEnterMonitor()
            unregisterDraggedTypes()
        }
    }

    private func startCursorKeepAlive() {
        cursorKeepAlive?.invalidate()
        // Schedule on .common modes so the timer survives scroll / event
        // tracking on the inspector divider, and pick a fast cadence to win
        // the race against claude's rendering bursts.
        // Timer block is typed @Sendable, but RunLoop.main fires it on the
        // main thread — MainActor.assumeIsolated lets us touch the
        // @MainActor-typed `terminal` property without an extra Task hop per
        // tick. assumeIsolated traps if the assumption is wrong, which it
        // never is for a RunLoop.main-scheduled Timer.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.terminal?.feed(text: "\u{1B}[?25h")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorKeepAlive = timer
    }

    override func hideCursor(source: Terminal) {
        // Intentionally empty — see class comment.
    }

    // claude's REPL submits on `\r` and treats `\n` as a soft newline / line
    // continuation — see commit 133e903 (runWorkflow CR-not-LF). SwiftTerm
    // maps Return (keyCode 36) and Numpad Enter (keyCode 76) to `\r` and
    // submits even with Shift held. `LocalProcessTerminalView.keyDown` is
    // `public override` but not `open`, so subclass-override is rejected
    // across module boundaries — a local NSEvent monitor (installed only
    // while the view is firstResponder) intercepts the keystroke first.
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
