nonisolated extension IssueColumn {
    var systemImage: String {
        switch self {
        case .todo: "tray"
        case .inProgress: "circle.dotted"
        case .waitingForReview: "eye"
        case .done: "checkmark.circle"
        }
    }
}
