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

    // nil for an empty column — the sole entering card sorts fine via ID fallback.
    static func topOrder(
        in columnItems: [DiscoveredIssue],
        excludingFolderName folderName: String? = nil
    ) -> Double? {
        let others = columnItems.filter { $0.id != folderName }
        guard let first = others.sortedForKanban().first else { return nil }
        return (first.orderValue ?? Double(first.idValue)) - 1.0
    }
}
