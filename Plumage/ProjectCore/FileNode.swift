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

    // True when any descendant (at any depth) is an empty context file — drives
    // the warning on a collapsed folder that hides such a file. Recomputed on
    // access; the trees are small and it is only read for folder rows.
    var containsEmptyContextFileDescendant: Bool {
        guard let children else { return false }
        return children.contains {
            $0.isEmptyContextFile || $0.containsEmptyContextFileDescendant
        }
    }

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
