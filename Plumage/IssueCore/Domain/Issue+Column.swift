nonisolated extension IssueStatus {
    var column: IssueColumn {
        switch self {
        case .draft, .approved, .blocked: .todo
        case .inProgress: .inProgress
        case .waitingForReview: .waitingForReview
        case .done: .done
        }
    }
}

nonisolated extension Issue {
    var column: IssueColumn { status.column }
}
