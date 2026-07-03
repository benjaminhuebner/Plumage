import Foundation

nonisolated enum BlockerState: Hashable, Sendable {
    case open
    case done
    case missing
}

nonisolated struct ResolvedBlocker: Hashable, Sendable {
    let folderName: String
    let state: BlockerState
    let id: Int?
    let title: String?
}

nonisolated enum BlockerResolution {
    static func index(_ issues: [DiscoveredIssue]) -> [String: DiscoveredIssue] {
        Dictionary(issues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func resolve(
        blockedBy: [String],
        of folderName: String,
        index: [String: DiscoveredIssue]
    ) -> [ResolvedBlocker] {
        var seen = Set<String>()
        var resolved: [ResolvedBlocker] = []
        for entry in blockedBy {
            guard entry != folderName, seen.insert(entry).inserted else { continue }
            switch index[entry] {
            case .valid(let issue):
                resolved.append(
                    ResolvedBlocker(
                        folderName: entry,
                        state: issue.status == .done ? .done : .open,
                        id: issue.id,
                        title: issue.title
                    )
                )
            case .invalid:
                // An unparseable spec is still an existing, unfinished issue —
                // it blocks; only a folder that is gone entirely is .missing.
                resolved.append(ResolvedBlocker(folderName: entry, state: .open, id: nil, title: nil))
            case nil:
                resolved.append(ResolvedBlocker(folderName: entry, state: .missing, id: nil, title: nil))
            }
        }
        return resolved
    }

    static func openBlockers(
        blockedBy: [String],
        of folderName: String,
        index: [String: DiscoveredIssue]
    ) -> [ResolvedBlocker] {
        resolve(blockedBy: blockedBy, of: folderName, index: index)
            .filter { $0.state == .open }
    }
}
