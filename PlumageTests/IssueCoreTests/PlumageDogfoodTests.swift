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
        try #require(FileManager.default.fileExists(atPath: claudeIssues.path))

        let issues = IssueDiscovery.discoverIssues(in: repoRoot)
        try #require(!issues.isEmpty)
        let ids = issues.map(\.id)
        #expect(ids == ids.sorted())
        #expect(ids.contains(3))
        for issue in issues {
            #expect(!issue.title.isEmpty)
            #expect(!issue.branch.isEmpty)
        }
    }
}
