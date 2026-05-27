import Foundation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let children: [FileNode]?

    var id: String { relativePath }
}
