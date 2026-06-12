import Foundation

// Inline-rename session for a content-tree row. `id` is the node id; `storePath` is the
// override-store path of the file/folder being renamed; `name` is bound by the row's
// `TextField`.
struct ContentRename: Identifiable, Equatable {
    let id: String
    let storePath: String
    let isDirectory: Bool
    var name: String
}
