import Foundation

nonisolated struct Issue: Hashable, Sendable {
    let id: Int
    let folder: String
    let title: String
    let type: IssueType
    let status: IssueStatus
    let created: Date
    let updated: Date
    let branch: String
    let labels: [String]
    let model: String?
}
