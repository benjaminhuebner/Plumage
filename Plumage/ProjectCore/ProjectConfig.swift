import Foundation

nonisolated struct ProjectConfig: Codable, Hashable, Sendable {
    let name: String
    let schemaVersion: Int
    let issueIdPadding: Int?
}
