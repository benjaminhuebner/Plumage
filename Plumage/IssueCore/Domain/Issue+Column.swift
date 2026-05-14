nonisolated extension Issue {
    var column: IssueColumn {
        switch status {
        case .draft, .approved, .blocked: .todo
        case .inProgress: .inProgress
        case .waitingForReview: .waitingForReview
        case .done: .done
        }
    }
}
