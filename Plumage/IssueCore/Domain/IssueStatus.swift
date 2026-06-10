import Foundation

nonisolated enum IssueStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case approved
    case inProgress = "in-progress"
    case waitingForReview = "waiting-for-review"
    case done
    case blocked

    // Tolerant Codable path (ModelChoice discipline): a value from a newer
    // build coerces to .draft instead of failing the container. Frontmatter
    // stays strict — SpecParser maps unknowns to the invalid-card surface.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = IssueStatus(rawValue: raw) ?? .draft
    }
}
