import AppKit
import SwiftUI

// A SwiftUI-hosted NSOutlineView stops receiving cross-process drops after any relayout;
// this click-transparent `.fileURL`-only overlay never relayouts, so Finder import stays
// repeatable. In-tree drags carry the custom type only and fall through to the outline.
struct ImportDropCatcher: NSViewRepresentable {
    // The drop location (window coords) lets a position-aware adopter resolve the target
    // under the cursor; fixed-scope callers ignore it.
    let onImport: ([URL], NSPoint) -> Void
    // Absent → any readable file-URL drag is a plain copy with no highlight.
    var onDragChange: ((NSPoint) -> NSDragOperation)?
    var onDragExit: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = ClickThroughDropView()
        view.configure(onImport: onImport, onDragChange: onDragChange, onDragExit: onDragExit)
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickThroughDropView)?.configure(
            onImport: onImport, onDragChange: onDragChange, onDragExit: onDragExit)
    }

    final class ClickThroughDropView: NSView {
        private var onImport: (([URL], NSPoint) -> Void)?
        private var onDragChange: ((NSPoint) -> NSDragOperation)?
        private var onDragExit: (() -> Void)?

        func configure(
            onImport: @escaping ([URL], NSPoint) -> Void,
            onDragChange: ((NSPoint) -> NSDragOperation)?,
            onDragExit: (() -> Void)?
        ) {
            self.onImport = onImport
            self.onDragChange = onDragChange
            self.onDragExit = onDragExit
        }

        // nil keeps clicks and in-tree drag starts flowing to the outline beneath;
        // drag-destination delivery is independent of hit-testing, so drops still land here.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            operation(for: sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            operation(for: sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            onDragExit?()
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            onDragExit?()
        }

        // Internal moves carry the custom type only and never reach here; this guards the
        // edge case of a pasteboard that ever carries both.
        private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
            let types = sender.draggingPasteboard.types ?? []
            guard !types.contains(FinderFileTreeCoordinator.internalDragType),
                sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self])
            else { return [] }
            if let onDragChange { return onDragChange(sender.draggingLocation) }
            return .copy
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            onDragExit?()
            let types = sender.draggingPasteboard.types ?? []
            guard !types.contains(FinderFileTreeCoordinator.internalDragType),
                let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])
                    as? [URL]
            else { return false }
            let files = objects.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            onImport?(files, sender.draggingLocation)
            return true
        }
    }
}
