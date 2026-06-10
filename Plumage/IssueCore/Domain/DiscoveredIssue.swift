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

    var sortKey: (Int, String) {
        switch self {
        case .valid(let issue):
            return (issue.id, issue.folderName.lowercased())
        case .invalid(let folder, _):
            let parts = IssueDiscovery.extractID(fromFolderName: folder.lastPathComponent)
            return (parts.id ?? .max, folder.lastPathComponent.lowercased())
        }
    }
}
