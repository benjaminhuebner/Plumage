import Foundation

nonisolated extension DiscoveredIssue {
    var orderValue: Double? {
        if case .valid(let issue) = self { issue.order } else { nil }
    }

    var idValue: Int {
        switch self {
        case .valid(let issue):
            issue.id
        case .invalid(let folder, _):
            IssueDiscovery.extractID(fromFolderName: folder.lastPathComponent).id ?? .max
        }
    }

    var folderKey: String {
        switch self {
        case .valid(let issue): issue.folderName.lowercased()
        case .invalid(let folder, _): folder.lastPathComponent.lowercased()
        }
    }
}

nonisolated extension Array where Element == DiscoveredIssue {
    func sortedForKanban() -> [DiscoveredIssue] {
        sorted { lhs, rhs in
            let lhsOrder = lhs.orderValue ?? Double(lhs.idValue)
            let rhsOrder = rhs.orderValue ?? Double(rhs.idValue)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if lhs.idValue != rhs.idValue { return lhs.idValue < rhs.idValue }
            return lhs.folderKey < rhs.folderKey
        }
    }
}
