nonisolated extension IssueColumn {
    var primaryStatusForCreation: IssueStatus {
        switch self {
        case .todo: .draft
        case .inProgress: .inProgress
        case .waitingForReview: .waitingForReview
        case .done: .done
        }
    }
}
