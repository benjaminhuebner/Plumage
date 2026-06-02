import Foundation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let children: [FileNode]?
    // A foundation context file (CLAUDE.md / PROJECT.md) that is effectively
    // empty — drives the sidebar warning icon. Always false for every other row.
    let isEmptyContextFile: Bool

    var id: String { relativePath }

    init(
        url: URL,
        relativePath: String,
        name: String,
        isDirectory: Bool,
        children: [FileNode]?,
        isEmptyContextFile: Bool = false
    ) {
        self.url = url
        self.relativePath = relativePath
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
        self.isEmptyContextFile = isEmptyContextFile
    }
}
