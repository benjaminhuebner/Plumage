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
