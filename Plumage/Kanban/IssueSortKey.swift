import Foundation

nonisolated extension IssueColumn {
    var canonicalDropStatus: IssueStatus {
        switch self {
        case .todo: .approved
        case .inProgress: .inProgress
        case .waitingForReview: .waitingForReview
        case .done: .done
        }
    }
}

nonisolated enum IssueSortKey {
    static func midOrder(above: Double?, below: Double?, fallbackID: Int) -> Double {
        switch (above, below) {
        case (.some(let lhs), .some(let rhs)): (lhs + rhs) / 2.0
        case (.some(let lhs), nil): lhs + 1.0
        case (nil, .some(let rhs)): rhs - 1.0
        case (nil, nil): Double(fallbackID)
        }
    }
}
