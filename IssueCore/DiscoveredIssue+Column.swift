extension DiscoveredIssue {
    var column: IssueColumn {
        switch self {
        case .invalid: .todo
        case .valid(let issue):
            switch issue.status {
            case .draft, .approved, .blocked: .todo
            case .inProgress: .inProgress
            case .waitingForReview: .waitingForReview
            case .done: .done
            }
        }
    }

    var isBlocked: Bool {
        if case .valid(let issue) = self { issue.status == .blocked } else { false }
    }
}
