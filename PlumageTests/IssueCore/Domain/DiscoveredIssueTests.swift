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
            labels: []
        )
    }
}
