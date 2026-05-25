import Foundation

nonisolated struct ProjectConfig: Codable, Hashable, Sendable {
    let name: String
    let schemaVersion: Int
    let issueIdPadding: Int?
    let git: GitConfig?

    var gitDefaultBranch: String {
        git?.defaultBranch ?? "main"
    }
}

nonisolated struct GitConfig: Codable, Hashable, Sendable {
    let defaultBranch: String?
}
