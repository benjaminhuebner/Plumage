import AppKit
import SwiftUI

struct WindowChromeCustomizer: NSViewRepresentable {
    let windowAlphaHidden: Bool

    func makeNSView(context: Context) -> NSView {
        ChromeCustomizingView(windowAlphaHidden: windowAlphaHidden)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ChromeCustomizingView else { return }
        view.applyWindowAlphaHidden(windowAlphaHidden)
    }

    private final class ChromeCustomizingView: NSView {
        private var windowAlphaHidden: Bool

        init(windowAlphaHidden: Bool) {
            self.windowAlphaHidden = windowAlphaHidden
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        func applyWindowAlphaHidden(_ hidden: Bool) {
            windowAlphaHidden = hidden
            window?.alphaValue = hidden ? 0 : 1
        }

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
            window.alphaValue = windowAlphaHidden ? 0 : 1
        }
    }
}
