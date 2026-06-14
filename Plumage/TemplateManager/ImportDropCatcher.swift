import AppKit
import SwiftUI

// The content tree's NSOutlineView stops receiving cross-process drops after any relayout
// (a SwiftUI-hosted layer-backing quirk); this click-transparent overlay above it never
// relayouts, so Finder import stays repeatable.
struct ImportDropCatcher: NSViewRepresentable {
    let onImport: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClickThroughDropView()
        view.onImport = onImport
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickThroughDropView)?.onImport = onImport
    }

    final class ClickThroughDropView: NSView {
        var onImport: (([URL]) -> Void)?

        // nil keeps clicks and in-tree drag starts flowing to the outline beneath;
        // drag-destination delivery is independent of hit-testing, so drops still land here.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            operation(for: sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            operation(for: sender)
        }

        // Internal moves carry only the custom type and never reach here; the guard is
        // insurance against a pasteboard that ever carries both.
        private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
            let types = sender.draggingPasteboard.types ?? []
            guard !types.contains(FinderFileTreeCoordinator.internalDragType) else { return [] }
            return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) ? .copy : []
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            let types = sender.draggingPasteboard.types ?? []
            guard !types.contains(FinderFileTreeCoordinator.internalDragType),
                let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
            else { return false }
            let files = objects.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            onImport?(files)
            return true
        }
    }
}
