import Foundation

nonisolated struct IssueFilter: Equatable, Sendable {
    var text: String = ""
    var selectedLabels: Set<String> = []
    var type: IssueType?
    var idPadWidth: Int = 5

    var isActive: Bool {
        !trimmedText.isEmpty || !selectedLabels.isEmpty || type != nil
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespaces)
    }

    func matches(_ discovered: DiscoveredIssue) -> Bool {
        switch discovered {
        case .valid(let issue):
            return matchesValid(issue)
        case .invalid(let folder, _):
            // Broken specs stay findable by text via their folder name, but
            // have no trustworthy labels/type to match a facet filter.
            guard selectedLabels.isEmpty, type == nil else { return false }
            return textMatches(candidates: [folder.lastPathComponent])
        }
    }

    private func matchesValid(_ issue: Issue) -> Bool {
        if let type, issue.type != type { return false }
        if !selectedLabels.isSubset(of: issue.labels) { return false }
        var candidates = [issue.title, IssueIDFormatter.padded(issue.id, width: idPadWidth)]
        candidates.append(contentsOf: issue.labels)
        return textMatches(candidates: candidates)
    }

    private func textMatches(candidates: [String]) -> Bool {
        var needle = trimmedText
        guard !needle.isEmpty else { return true }
        if needle.hasPrefix("#") { needle = String(needle.dropFirst()) }
        let folded = Self.fold(needle)
        return candidates.contains { Self.fold($0).contains(folded) }
    }

    private static func fold(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
