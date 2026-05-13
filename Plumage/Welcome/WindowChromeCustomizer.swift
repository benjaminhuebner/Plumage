import AppKit
import SwiftUI

struct WindowChromeCustomizer: NSViewRepresentable {
    var hiddenOnFirstShow: Bool = false

    func makeNSView(context: Context) -> NSView {
        ChromeCustomizingView(hiddenOnFirstShow: hiddenOnFirstShow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeCustomizingView: NSView {
        private let hiddenOnFirstShow: Bool

        init(hiddenOnFirstShow: Bool) {
            self.hiddenOnFirstShow = hiddenOnFirstShow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
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
            if hiddenOnFirstShow {
                window.alphaValue = 0
            }
        }
    }
}
