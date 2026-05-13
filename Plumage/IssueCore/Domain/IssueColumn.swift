nonisolated enum IssueColumn: String, CaseIterable, Identifiable, Sendable {
    case todo
    case inProgress
    case waitingForReview
    case done

    var id: String { rawValue }

    var name: String {
        switch self {
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .waitingForReview: "Waiting for Review"
        case .done: "Done"
        }
    }
}
