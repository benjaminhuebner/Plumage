import Foundation
import Testing

@testable import Plumage

@Suite("Plumage dogfood")
struct PlumageDogfoodTests {
    @Test("discovers Plumage's own active issues with valid frontmatter")
    func discoversOwnIssues() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let claudeIssues = repoRoot.appendingPathComponent(".claude/issues")
        // .claude/ is locally excluded from git (.git/info/exclude); skip on fresh CI checkouts.
        guard FileManager.default.fileExists(atPath: claudeIssues.path) else { return }

        let discovered = IssueDiscovery.discoverIssues(in: repoRoot)
        try #require(!discovered.isEmpty)
        let validIssues: [Plumage.Issue] = discovered.compactMap {
            if case .valid(let issue) = $0 { return issue }
            return nil
        }
        try #require(!validIssues.isEmpty)
        // discoverIssues returns issues in sortedForKanban order: by
        // orderValue (with idValue as fallback), then by idValue, then
        // by folderKey. The kanban-sort is not always ID-ascending —
        // reorders write explicit `order:` fields that shift positions.
        // Validate non-decreasing sort keys instead of strict ID ascending.
        let sortKeys = validIssues.map { ($0.order ?? Double($0.id), $0.id) }
        for (previous, next) in zip(sortKeys, sortKeys.dropFirst()) {
            let nonDescending =
                previous.0 < next.0
                || (previous.0 == next.0 && previous.1 < next.1)
            #expect(nonDescending, "\(sortKeys) is not in sortedForKanban order")
        }
        for issue in validIssues {
            #expect(!issue.title.isEmpty)
            #expect(!issue.branch.isEmpty)
            #expect(!issue.folderName.isEmpty)
        }
    }
}
