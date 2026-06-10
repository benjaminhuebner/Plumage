import Foundation

nonisolated enum IssueType: String, CaseIterable, Codable, Sendable {
    case feature
    case chore
    case spike
    case refactor

    // Tolerant Codable path (ModelChoice discipline) — see IssueStatus.
    // Frontmatter stays strict via SpecParser's raw-value validation.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = IssueType(rawValue: raw) ?? .chore
    }
}
