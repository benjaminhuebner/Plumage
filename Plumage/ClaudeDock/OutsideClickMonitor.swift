import AppKit
import SwiftUI

struct OutsideClickMonitor: NSViewRepresentable {
    let isActive: Bool
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.onClickOutside = onClickOutside
        view.setActive(isActive)
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        nsView.onClickOutside = onClickOutside
        nsView.setActive(isActive)
    }

    final class MonitorHostView: NSView {
        var onClickOutside: (() -> Void)?
        // nonisolated(unsafe) lets deinit (always nonisolated) tear down the
        // monitor token without going through a MainActor-isolated method.
        // NSEvent.removeMonitor is thread-safe; only this view owns the token.
        nonisolated(unsafe) private var monitor: Any?
        private var wantsActive = false

        func setActive(_ active: Bool) {
            wantsActive = active
            refreshMonitor()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func refreshMonitor() {
            if wantsActive && window != nil {
                installMonitor()
            } else {
                removeMonitor()
            }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                if self.shouldSwallow(event) {
                    self.onClickOutside?()
                    return nil
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func shouldSwallow(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            let frameInWindow = convert(bounds, to: nil)
            return !frameInWindow.contains(event.locationInWindow)
        }
    }
}
