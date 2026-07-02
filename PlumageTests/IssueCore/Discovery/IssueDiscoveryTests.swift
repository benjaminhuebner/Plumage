import Foundation
import Testing

@testable import Plumage

@Suite("IssueDiscovery")
struct IssueDiscoveryTests {
    @Test("returns empty for project without .claude/issues")
    func missingIssuesDir() throws {
        let project = try makeTempProject()
        #expect(IssueDiscovery.discoverIssues(in: project).isEmpty)
    }

    @Test("returns empty for an empty issues dir")
    func emptyIssuesDir() throws {
        let project = try makeTempProject()
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".claude/issues"),
            withIntermediateDirectories: true
        )
        #expect(IssueDiscovery.discoverIssues(in: project).isEmpty)
    }

    @Test("returns valid issues sorted by id ascending")
    func sortsAscending() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00010-third", id: 10, type: "feature")
        try writeIssue(in: project, folder: "00002-first", id: 2, type: "chore")
        try writeIssue(in: project, folder: "00005-second", id: 5, type: "spike")
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issueIds(issues) == [2, 5, 10])
    }

    @Test("invalid specs land as .invalid in the list, sorted by extracted id")
    func includesInvalid() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        try writeRaw(in: project, folder: "00002-broken", content: "no frontmatter here")
        try writeIssue(in: project, folder: "00003-valid", id: 3, type: "chore")

        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issues.count == 3)
        guard case .invalid(let folder, let error) = issues[1] else {
            Testing.Issue.record("expected .invalid at index 1, got \(issues[1])")
            return
        }
        #expect(folder.lastPathComponent == "00002-broken")
        #expect(error == .missingFrontmatter)
    }

    @Test("invalid rows interleave with valid rows by extracted id")
    func interleavedSorting() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        try writeRaw(in: project, folder: "00002-broken", content: "no frontmatter here")
        try writeIssue(in: project, folder: "00003-valid", id: 3, type: "chore")
        try writeRaw(in: project, folder: "00004-also-broken", content: "no frontmatter")

        let issues = IssueDiscovery.discoverIssues(in: project)
        let names = issues.map(folderName(for:))
        #expect(names == ["00001-valid", "00002-broken", "00003-valid", "00004-also-broken"])
    }

    @Test("invalid folder without id prefix lands at the end")
    func nonIdPrefixGoesToEnd() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        try writeRaw(in: project, folder: "no-id-prefix", content: "no frontmatter")
        try writeIssue(in: project, folder: "00005-valid", id: 5, type: "chore")

        let issues = IssueDiscovery.discoverIssues(in: project)
        let names = issues.map(folderName(for:))
        #expect(names == ["00001-valid", "00005-valid", "no-id-prefix"])
    }

    @Test("invalid folder with non-numeric prefix lands at the end")
    func nonNumericPrefixGoesToEnd() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        try writeRaw(in: project, folder: "abc-something", content: "no frontmatter")

        let issues = IssueDiscovery.discoverIssues(in: project)
        let names = issues.map(folderName(for:))
        #expect(names == ["00001-valid", "abc-something"])
    }

    @Test("ignores archive folder")
    func ignoresArchive() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-live", id: 1, type: "feature")
        let archiveDir = project.appendingPathComponent(".claude/issues/archive/00099-old")
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let archived = makeFrontmatter(id: 99, type: "feature", branch: "issue/00099-old")
        try archived.write(
            to: archiveDir.appendingPathComponent("spec.md"),
            atomically: true,
            encoding: .utf8
        )
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issueIds(issues) == [1])
    }

    @Test("ignores loose files at .claude/issues root")
    func ignoresLooseFiles() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-real", id: 1, type: "feature")
        let issuesDir = project.appendingPathComponent(".claude/issues")
        try "template content".write(
            to: issuesDir.appendingPathComponent("_TEMPLATE.md"),
            atomically: true,
            encoding: .utf8
        )
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issueIds(issues) == [1])
    }

    @Test("breaks duplicate-id ties by folder name ascending")
    func duplicateIdsTieBreak() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00007-bravo", id: 7, type: "feature")
        try writeIssue(in: project, folder: "00007-alpha", id: 7, type: "chore")
        try writeIssue(in: project, folder: "00007-charlie", id: 7, type: "spike")
        let issues = IssueDiscovery.discoverIssues(in: project)
        let names = issues.map(folderName(for:))
        #expect(names == ["00007-alpha", "00007-bravo", "00007-charlie"])
    }

    @Test("folders without spec.md are skipped")
    func skipsFoldersWithoutSpec() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        let emptyDir = project.appendingPathComponent(".claude/issues/00002-no-spec")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issues.count == 1)
        #expect(folderName(for: issues[0]) == "00001-valid")
    }

    @Suite("extractID")
    struct ExtractID {
        @Test("padded id and slug")
        func paddedIdAndSlug() {
            let parts = IssueDiscovery.extractID(fromFolderName: "00042-broken-stuff")
            #expect(parts.id == 42)
            #expect(parts.slug == "broken-stuff")
        }

        @Test("non-padded id and slug")
        func nonPaddedIdAndSlug() {
            let parts = IssueDiscovery.extractID(fromFolderName: "7-bravo")
            #expect(parts.id == 7)
            #expect(parts.slug == "bravo")
        }

        @Test("missing dash returns full name as slug, nil id")
        func missingDash() {
            let parts = IssueDiscovery.extractID(fromFolderName: "no-id-prefix")
            // first dash is between "no" and "id" — prefix "no" is not Int → falls back
            #expect(parts.id == nil)
            #expect(parts.slug == "no-id-prefix")
        }

        @Test("non-numeric prefix returns full name as slug, nil id")
        func nonNumericPrefix() {
            let parts = IssueDiscovery.extractID(fromFolderName: "abc-something")
            #expect(parts.id == nil)
            #expect(parts.slug == "abc-something")
        }

        @Test("no dash at all returns full name as slug, nil id")
        func noDash() {
            let parts = IssueDiscovery.extractID(fromFolderName: "loose")
            #expect(parts.id == nil)
            #expect(parts.slug == "loose")
        }
    }

    private func issueIds(_ issues: [DiscoveredIssue]) -> [Int] {
        issues.compactMap {
            if case .valid(let issue) = $0 { return issue.id }
            return nil
        }
    }

    @Test("evidence.json changes the issue's evidence stamp; absence yields nil")
    func evidenceStampTracksFile() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-with-evidence", id: 1, type: "feature")

        let before = IssueDiscovery.discoverIssues(in: project)
        guard case .valid(let unstamped) = try #require(before.first) else {
            Testing.Issue.record("expected .valid, got \(before)")
            return
        }
        #expect(unstamped.evidenceStamp == nil)

        let evidenceURL = project.appendingPathComponent(
            ".claude/issues/00001-with-evidence/evidence.json")
        try #"{"version": 1, "issue": "00001-with-evidence"}"#
            .write(to: evidenceURL, atomically: true, encoding: .utf8)
        let after = IssueDiscovery.discoverIssues(in: project)
        guard case .valid(let stamped) = try #require(after.first) else {
            Testing.Issue.record("expected .valid, got \(after)")
            return
        }
        let firstStamp = try #require(stamped.evidenceStamp)

        try #"{"version": 1, "issue": "00001-with-evidence", "tasks": []}"#
            .write(to: evidenceURL, atomically: true, encoding: .utf8)
        let rewritten = IssueDiscovery.discoverIssues(in: project)
        guard case .valid(let restamped) = try #require(rewritten.first) else {
            Testing.Issue.record("expected .valid, got \(rewritten)")
            return
        }
        #expect(restamped.evidenceStamp != nil)
        #expect(restamped.evidenceStamp != firstStamp)
        #expect(before != after)
    }

    private func folderName(for discovered: DiscoveredIssue) -> String {
        switch discovered {
        case .valid(let issue): issue.folderName
        case .invalid(let folder, _): folder.lastPathComponent
        }
    }

    private func makeTempProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageIssueDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeIssue(in project: URL, folder: String, id: Int, type: String) throws {
        let dir = project.appendingPathComponent(".claude/issues/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = makeFrontmatter(id: id, type: type, branch: "issue/\(folder)")
        try content.write(to: dir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    }

    private func writeRaw(in project: URL, folder: String, content: String) throws {
        let dir = project.appendingPathComponent(".claude/issues/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    }

    private func makeFrontmatter(id: Int, type: String, branch: String) -> String {
        """
        ---
        id: \(id)
        title: Issue \(id)
        type: \(type)
        status: approved
        created: 2026-05-12T09:00:00Z
        updated: 2026-05-12T10:00:00Z
        branch: \(branch)
        labels: []
        model: null
        ---

        Body.
        """
    }
}
