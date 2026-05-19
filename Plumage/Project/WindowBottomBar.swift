import AppKit
import SwiftUI

// Installs a native NSWindow bottom bar (NSTitlebarAccessoryViewController
// with .bottom layoutAttribute) wrapping the given SwiftUI content. Unlike
// a plain SwiftUI footer, this lives in the window's chrome — same material,
// border, and integrated look as Finder's status bar or Xcode's mini-toolbar.
//
// Usage: attach as an invisible background to any view that's already mounted
// in the target window. The NSView itself has zero frame and renders nothing.
struct WindowBottomBar<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let content = self.content
        Task { @MainActor [weak view] in
            guard let view, let window = view.window else { return }
            context.coordinator.attach(to: window, rootView: content)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let content = self.content
        Task { @MainActor [weak nsView] in
            if let hosting = context.coordinator.hostingController {
                hosting.rootView = content
            } else if let window = nsView?.window {
                context.coordinator.attach(to: window, rootView: content)
            }
        }
    }

    @MainActor
    final class Coordinator {
        var hostingController: NSHostingController<Content>?
        weak var accessoryController: NSTitlebarAccessoryViewController?

        func attach(to window: NSWindow, rootView: Content) {
            guard accessoryController == nil else { return }
            let hosting = NSHostingController(rootView: rootView)
            // .preferredContentSize lets the SwiftUI content drive its own
            // height; without it the accessory view collapses to 0pt.
            hosting.sizingOptions = [.preferredContentSize]
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = hosting.view
            accessory.layoutAttribute = .bottom
            window.addTitlebarAccessoryViewController(accessory)
            hostingController = hosting
            accessoryController = accessory
        }
    }
}
