import Foundation
import Testing

@testable import Plumage

@Suite("DiscoveredIssue")
struct DiscoveredIssueTests {
    @Test("id distinguishes valid from invalid for the same folder name")
    func idDistinguishesValidFromInvalid() {
        let valid = DiscoveredIssue.valid(sampleIssue(id: 1, folder: "00001-foo"))
        let invalid = DiscoveredIssue.invalid(
            folder: URL(filePath: "/tmp/x/.claude/issues/00001-foo"),
            error: .missingFrontmatter
        )
        #expect(valid.id != invalid.id)
    }

    @Test("id is stable per case")
    func idStability() {
        let valid1 = DiscoveredIssue.valid(sampleIssue(id: 1, folder: "00001-foo"))
        let valid2 = DiscoveredIssue.valid(sampleIssue(id: 1, folder: "00001-foo"))
        #expect(valid1.id == valid2.id)

        let url = URL(filePath: "/tmp/x/.claude/issues/00002-bar")
        let invalid1 = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        let invalid2 = DiscoveredIssue.invalid(
            folder: url,
            error: .invalidEnumValue(field: "status", value: "x")
        )
        #expect(invalid1.id == invalid2.id)
    }

    @Test("sortKey for valid uses issue id and folder name")
    func sortKeyValid() {
        let issue = DiscoveredIssue.valid(sampleIssue(id: 7, folder: "00007-bravo"))
        let key = issue.sortKey
        #expect(key.0 == 7)
        #expect(key.1 == "00007-bravo")
    }

    @Test("sortKey for invalid with extractable id uses that id")
    func sortKeyInvalidExtractableId() {
        let invalid = DiscoveredIssue.invalid(
            folder: URL(filePath: "/x/00042-broken"),
            error: .missingFrontmatter
        )
        let key = invalid.sortKey
        #expect(key.0 == 42)
        #expect(key.1 == "00042-broken")
    }

    @Test("sortKey for invalid without extractable id falls back to Int.max")
    func sortKeyInvalidFallback() {
        let invalid = DiscoveredIssue.invalid(
            folder: URL(filePath: "/x/no-id-prefix"),
            error: .missingFrontmatter
        )
        let key = invalid.sortKey
        #expect(key.0 == .max)
        #expect(key.1 == "no-id-prefix")
    }

    @Test("folderURL returns the URL for invalid and a folder-string-URL for valid")
    func folderURL() {
        let url = URL(filePath: "/x/00042-broken")
        let invalid = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        #expect(invalid.folderURL == url)

        let valid = DiscoveredIssue.valid(sampleIssue(id: 1, folder: "00001-foo"))
        #expect(valid.folderURL.lastPathComponent == "00001-foo")
    }

    private func sampleIssue(id: Int, folder: String) -> Plumage.Issue {
        Plumage.Issue(
            id: id,
            folder: folder,
            title: "Title \(id)",
            type: .feature,
            status: .approved,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/\(folder)",
            labels: [],
            model: nil
        )
    }
}
