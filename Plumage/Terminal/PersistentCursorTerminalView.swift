import AppKit
// @preconcurrency: SwiftTerm 1.13.0 has no Swift 6 Sendable annotations.
// LocalProcess defaults its dispatch queue to DispatchQueue.main, so delegate
// callbacks arrive on the main thread.
@preconcurrency import SwiftTerm

// claude's REPL sends DECRST 25 (hide cursor) while rendering; the no-op
// hideCursor override below keeps SwiftTerm from tearing down the caret view,
// so the cursor stays solid without re-feeding `\e[?25h` on a timer.
final class PersistentCursorTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // Fallback when dismantleNSView was skipped (normal teardown nils these on
        // MainActor, making this a no-op). NSEvent.removeMonitor is main-thread-only
        // and deinit can run off-main — ferry onto the main queue.
        guard keyMappingMonitor != nil || mouseFocusMonitor != nil || scrollMonitor != nil
        else { return }
        // @unchecked Sendable: only carries the main-thread-bound references
        // across the queue hop; nothing reads them concurrently.
        struct Teardown: @unchecked Sendable {
            let tokens: [Any]
        }
        let teardown = Teardown(
            tokens: [keyMappingMonitor, mouseFocusMonitor, scrollMonitor].compactMap { $0 }
        )
        keyMappingMonitor = nil
        mouseFocusMonitor = nil
        scrollMonitor = nil
        if Thread.isMainThread {
            teardown.tokens.forEach { NSEvent.removeMonitor($0) }
        } else {
            DispatchQueue.main.async {
                teardown.tokens.forEach { NSEvent.removeMonitor($0) }
            }
        }
    }

    // Visibility gate for the keep-alive timer + key monitor: the inspector hides
    // its column instead of unmounting, and hidden tabs stay ZStack-mounted —
    // without this every terminal kept its timer burning behind a closed inspector.
    var chromeActive = true {
        didSet {
            guard chromeActive != oldValue else { return }
            refreshChrome()
        }
    }

    // SwiftTerm's scrollWheel is `public`, not `open` — it can't be overridden
    // from this module, so a local monitor intercepts the wheel (like the
    // mouseFocus/shiftEnter monitors below).
    nonisolated(unsafe) private var scrollMonitor: Any?
    private var scrollAccumulator = TerminalWheelAccumulator()

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self else { return event }
            return self.forwardScrollToTerminal(event) ? nil : event
        }
    }

    func removeScrollMonitor() {
        if let token = scrollMonitor {
            NSEvent.removeMonitor(token)
            scrollMonitor = nil
        }
    }

    // claude's TUI lives in the alternate buffer, where SwiftTerm's own
    // scrollback can't move — forward the wheel as the mouse-wheel buttons
    // (Cb 64/65) claude already listens for so its transcript scrolls.
    private func forwardScrollToTerminal(_ event: NSEvent) -> Bool {
        guard let terminal, let window, window === event.window,
            bounds.contains(convert(event.locationInWindow, from: nil))
        else { return false }
        guard terminal.mouseMode != .off else { return false }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            scrollAccumulator.reset()
        }
        let notches =
            event.hasPreciseScrollingDeltas
            ? scrollAccumulator.notches(forPreciseDelta: Double(event.scrollingDeltaY))
            : scrollAccumulator.notches(forLineDelta: Double(event.deltaY))
        guard let button = TerminalWheelAccumulator.button(forNotchDirection: notches) else {
            return true
        }
        let cell = terminalCell(for: event)
        let flags = terminal.encodeButton(
            button: button, release: false,
            shift: event.modifierFlags.contains(.shift),
            meta: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control))
        for _ in 0..<abs(notches) {
            terminal.sendEvent(buttonFlags: flags, x: cell.col, y: cell.row)
        }
        return true
    }

    private func terminalCell(for event: NSEvent) -> (col: Int, row: Int) {
        guard let terminal, bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        let point = convert(event.locationInWindow, from: nil)
        let col = min(
            max(Int(point.x / bounds.width * CGFloat(terminal.cols)), 0), terminal.cols - 1)
        // NSView is not flipped (origin bottom-left); terminal row 0 is the top.
        let row = min(
            max(Int((bounds.height - point.y) / bounds.height * CGFloat(terminal.rows)), 0),
            terminal.rows - 1)
        return (col, row)
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
            removeKeyMappingMonitor()
            removeMouseFocusMonitor()
            removeScrollMonitor()
            unregisterDraggedTypes()
        }
    }

    private func refreshChrome() {
        if window != nil && chromeActive {
            installKeyMappingMonitor()
            installMouseFocusMonitor()
            installScrollMonitor()
        } else {
            removeKeyMappingMonitor()
            removeMouseFocusMonitor()
            removeScrollMonitor()
        }
    }

    // No-op so claude's DECRST 25 (hide cursor) doesn't tear down the caret view;
    // keeps the cursor solid without a re-show timer (see class comment).
    override func hideCursor(source: Terminal) {}

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
        let selectAllItem = NSMenuItem(
            title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)
        return menu
    }

    // Shift+Enter soft newline plus the macOS-native editing chords from
    // TerminalKeyMapping (⌘⌫, ⌥⌫, ⌘/⌥-arrows). SwiftTerm's keyDown isn't `open` —
    // a local NSEvent monitor (only while firstResponder) intercepts first.
    nonisolated(unsafe) private var keyMappingMonitor: Any?

    private func installKeyMappingMonitor() {
        guard keyMappingMonitor == nil else { return }
        keyMappingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                let window = self.window,
                window === event.window,
                window.firstResponder === self,
                let sequence = TerminalKeyMapping.sequence(for: event)
            else { return event }
            self.send(txt: sequence)
            return nil
        }
    }

    func removeKeyMappingMonitor() {
        if let token = keyMappingMonitor {
            NSEvent.removeMonitor(token)
            keyMappingMonitor = nil
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
}
