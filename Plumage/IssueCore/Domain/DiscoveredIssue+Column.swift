nonisolated extension DiscoveredIssue {
    var column: IssueColumn {
        switch self {
        case .invalid: .todo
        case .valid(let issue): issue.column
        }
    }

    var isBlocked: Bool {
        if case .valid(let issue) = self { issue.status == .blocked } else { false }
    }
}
