extension DiscoveredIssue {
    var column: IssueColumn {
        switch self {
        case .invalid:
            return .todo
        case .valid(let issue):
            switch issue.status {
            case .draft, .approved, .blocked: return .todo
            case .inProgress: return .inProgress
            case .waitingForReview: return .waitingForReview
            case .done: return .done
            }
        }
    }

    var isBlocked: Bool {
        if case .valid(let issue) = self { return issue.status == .blocked }
        return false
    }
}
