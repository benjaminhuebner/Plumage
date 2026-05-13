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
        let ids = validIssues.map(\.id)
        #expect(ids == ids.sorted())
        for issue in validIssues {
            #expect(!issue.title.isEmpty)
            #expect(!issue.branch.isEmpty)
            #expect(!issue.folder.isEmpty)
        }
    }
}
