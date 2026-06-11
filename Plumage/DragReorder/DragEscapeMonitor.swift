import AppKit

// .onKeyPress(.escape) does not reliably fire while a mouse drag holds the
// responder chain; a local NSEvent monitor catches the keystroke regardless
// of focus and lets the surface cancel its drag mid-gesture.
enum DragEscapeMonitor {
    // Suspends until the caller's .task(id:) cancels it — cancellation runs
    // the defer and removes the monitor synchronously, leaving no trailing
    // window where ESC is still swallowed past drag-end.
    static func run(onEscape: @escaping @MainActor () -> Void) async {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @Sendable event in
            if event.keyCode == 53 {
                Task { @MainActor in onEscape() }
                return nil
            }
            return event
        }
        defer {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                break
            }
        }
    }
}
