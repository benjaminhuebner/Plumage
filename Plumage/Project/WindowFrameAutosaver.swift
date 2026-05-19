import AppKit
import SwiftUI

struct WindowFrameAutosaver: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // AppKit autosaves the frame to UserDefaults under this key,
            // independent of SwiftUI's scene restoration (which Plumage
            // disables to prevent project windows from auto-reopening on
            // launch).
            window.setFrameAutosaveName(autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
