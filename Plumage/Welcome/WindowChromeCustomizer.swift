import AppKit
import SwiftUI

struct WindowChromeCustomizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ChromeCustomizingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeCustomizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
