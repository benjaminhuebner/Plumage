import Foundation

nonisolated enum IssueStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case approved
    case inProgress = "in-progress"
    case waitingForReview = "waiting-for-review"
    case done
    case blocked

    // Tolerant Codable path (ModelChoice discipline): only serialized
    // payloads (drag payloads, caches) decode through here — a value from a
    // newer build coerces to .draft instead of failing the whole container.
    // Spec frontmatter does NOT take this path: SpecParser validates the raw
    // string itself and maps unknown statuses to the invalid-card surface.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = IssueStatus(rawValue: raw) ?? .draft
    }
}
