import Foundation

nonisolated enum DiscoveredIssue: Identifiable, Sendable {
    case valid(Issue)
    case invalid(folder: URL, error: FrontmatterError)

    var id: String {
        switch self {
        case .valid(let issue):
            "valid-\(issue.folder)"
        case .invalid(let folder, _):
            "invalid-\(folder.lastPathComponent)"
        }
    }

    var folderURL: URL {
        switch self {
        case .valid(let issue):
            URL(filePath: issue.folder)
        case .invalid(let folder, _):
            folder
        }
    }

    var sortKey: (Int, String) {
        switch self {
        case .valid(let issue):
            return (issue.id, issue.folder.lowercased())
        case .invalid(let folder, _):
            let parts = IssueDiscovery.extractID(fromFolderName: folder.lastPathComponent)
            return (parts.id ?? .max, folder.lastPathComponent.lowercased())
        }
    }
}
