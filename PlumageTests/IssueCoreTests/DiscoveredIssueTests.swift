import Foundation
import Testing

@testable import Plumage

@Suite("DiscoveredIssue")
struct DiscoveredIssueTests {
    @Test("id is the folder name and is stable across valid↔invalid flips")
    func idStableAcrossValidInvalidFlip() {
        let folder = "00001-foo"
        let url = URL(filePath: "/tmp/x/.claude/issues/\(folder)")
        let valid = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: folder))
        let invalid = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)

        #expect(valid.id == folder)
        #expect(invalid.id == folder)
        #expect(valid.id == invalid.id)
    }

    @Test("id is stable per case")
    func idStability() {
        let valid1 = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo"))
        let valid2 = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo"))
        #expect(valid1.id == valid2.id)

        let url = URL(filePath: "/tmp/x/.claude/issues/00002-bar")
        let invalid1 = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        let invalid2 = DiscoveredIssue.invalid(
            folder: url,
            error: .invalidEnumValue(field: "status", value: "x")
        )
        #expect(invalid1.id == invalid2.id)
    }

    @Test("Equatable: same case and payload compares equal")
    func equatableSame() {
        let lhs = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo"))
        let rhs = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo"))
        #expect(lhs == rhs)

        let url = URL(filePath: "/tmp/x/.claude/issues/00002-bar")
        let invalidLhs = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        let invalidRhs = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        #expect(invalidLhs == invalidRhs)
    }

    @Test("Equatable: differing payload compares unequal")
    func equatableDiffering() {
        let lhs = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo"))
        let rhs = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: "00001-foo", title: "Other"))
        #expect(lhs != rhs)

        let url = URL(filePath: "/tmp/x/.claude/issues/00002-bar")
        let invalidLhs = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        let invalidRhs = DiscoveredIssue.invalid(
            folder: url,
            error: .invalidEnumValue(field: "status", value: "x")
        )
        #expect(invalidLhs != invalidRhs)
    }

    @Test("Equatable: valid vs invalid for the same folder are unequal despite matching id")
    func equatableValidVsInvalidSameFolder() {
        let folder = "00001-foo"
        let url = URL(filePath: "/tmp/x/.claude/issues/\(folder)")
        let valid = DiscoveredIssue.valid(sampleIssue(id: 1, folderName: folder))
        let invalid = DiscoveredIssue.invalid(folder: url, error: .missingFrontmatter)
        #expect(valid != invalid)
    }

    @Test("sortKey for valid uses issue id and folder name")
    func sortKeyValid() {
        let issue = DiscoveredIssue.valid(sampleIssue(id: 7, folderName: "00007-bravo"))
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

    private func sampleIssue(
        id: Int,
        folderName: String,
        title: String? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id,
            folderName: folderName,
            title: title ?? "Title \(id)",
            type: .feature,
            status: .approved,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/\(folderName)",
            labels: [],
            model: nil
        )
    }
}
