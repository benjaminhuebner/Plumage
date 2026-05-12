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

    @Test("returns issues sorted by id ascending")
    func sortsAscending() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00010-third", id: 10, type: "feature")
        try writeIssue(in: project, folder: "00002-first", id: 2, type: "chore")
        try writeIssue(in: project, folder: "00005-second", id: 5, type: "spike")
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issues.map(\.id) == [2, 5, 10])
    }

    @Test("skips invalid specs silently")
    func skipsInvalid() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00001-valid", id: 1, type: "feature")
        try writeRaw(in: project, folder: "00002-broken", content: "no frontmatter here")
        try writeIssue(in: project, folder: "00003-valid", id: 3, type: "chore")
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issues.map(\.id) == [1, 3])
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
        #expect(issues.map(\.id) == [1])
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
        #expect(issues.map(\.id) == [1])
    }

    @Test("breaks duplicate-id ties by folder name ascending")
    func duplicateIdsTieBreak() throws {
        let project = try makeTempProject()
        try writeIssue(in: project, folder: "00007-bravo", id: 7, type: "feature")
        try writeIssue(in: project, folder: "00007-alpha", id: 7, type: "chore")
        try writeIssue(in: project, folder: "00007-charlie", id: 7, type: "spike")
        let issues = IssueDiscovery.discoverIssues(in: project)
        #expect(issues.map(\.type) == [.chore, .feature, .spike])
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
