import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// In-app drag payload for moving a node within the sidebar file tree.
// `absolutePath` keeps the URL form so the receiving folder can call
// `ClaudeProjectFiles.moveItem(at:to:)` with no further resolution. The
// Transferable type is registered in Info.plist as
// `com.benjaminhuebner.plumage.file-tree-drag` so the OS knows the UT exists
// and routes the drop back to our process.
nonisolated struct FileTreeDragPayload: Codable, Sendable, Hashable {
    let absolutePath: String

    init(url: URL) {
        self.absolutePath = url.standardizedFileURL.path
    }

    var url: URL {
        URL(fileURLWithPath: absolutePath)
    }
}

nonisolated extension UTType {
    static let plumageFileTreeDrag = UTType(
        exportedAs: "com.benjaminhuebner.plumage.file-tree-drag")
}

nonisolated extension FileTreeDragPayload: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plumageFileTreeDrag)
    }
}

// A folder row accepts BOTH Finder URL drops and tree-internal node drags.
// Stacking two `.dropDestination` modifiers on one view fires only the
// outermost (CoreTransferable ref: "stacking may cause only the outermost
// handler to fire") — so a single drop type wraps both and the handler
// switches on the case. Order matters: the richest representation
// (`FileTreeDragPayload`) is listed first so an internal drag resolves to
// `.internalNode`; a Finder drag carries only a file URL and falls through
// to `.finderURL`.
nonisolated enum DroppableTreeItem: Transferable {
    case internalNode(FileTreeDragPayload)
    case finderURL(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (payload: FileTreeDragPayload) in
            DroppableTreeItem.internalNode(payload)
        }
        ProxyRepresentation { (url: URL) in
            DroppableTreeItem.finderURL(url)
        }
    }
}
