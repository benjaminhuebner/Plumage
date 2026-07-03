import Foundation

nonisolated enum DiscoveredIssue: Identifiable, Equatable, Sendable {
    case valid(Issue)
    case invalid(folder: URL, error: FrontmatterError)

    // Folder-keyed: same folder keeps the same id across valid↔invalid flips,
    // so SwiftUI morphs the card in place instead of remove+insert.
    var id: String {
        switch self {
        case .valid(let issue):
            issue.folderName
        case .invalid(let folder, _):
            folder.lastPathComponent
        }
    }
}

nonisolated extension Sequence where Element == DiscoveredIssue {
    func unionedLabels() -> Set<String> {
        var all = Set<String>()
        for case .valid(let issue) in self {
            all.formUnion(issue.labels)
        }
        return all
    }
}
