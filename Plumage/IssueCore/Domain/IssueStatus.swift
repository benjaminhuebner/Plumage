nonisolated enum IssueStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case approved
    case inProgress = "in-progress"
    case waitingForReview = "waiting-for-review"
    case done
    case blocked
}
