import AppKit
import SwiftUI

struct WindowFrameAutosaver: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Defer until SwiftUI has installed the NSView in its window. Using
        // Task { @MainActor } over DispatchQueue.main.async keeps the hop
        // visible to the actor executor and consistent with the rest of the
        // codebase. AppKit autosaves the frame to UserDefaults under this
        // key, independent of SwiftUI's scene restoration (which Plumage
        // disables to prevent project windows from auto-reopening on launch).
        Task { @MainActor in
            guard let window = view.window else { return }
            window.setFrameAutosaveName(autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
