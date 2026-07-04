import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ProjectKanbanModel adoptedGitHubNumbers")
struct ProjectKanbanModelAdoptedTests {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "KanbanAdopt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".claude/issues"), withIntermediateDirectories: true)
        return root
    }

    private func writeArchiveSpec(in project: URL, folder: String, github: Int?) throws {
        let dir = project.appending(path: ".claude/issues/archive/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let githubLine = github.map { "github: \($0)\n" } ?? ""
        let spec = """
            ---
            id: \(github ?? 1)
            title: t
            type: feature
            status: done
            created: 2026-01-01T00:00:00Z
            updated: 2026-01-01T00:00:00Z
            branch: issue/\(folder)
            labels: []
            \(githubLine)---

            Body.
            """
        try spec.write(to: dir.appending(path: "spec.md"), atomically: true, encoding: .utf8)
    }

    private func validIssue(github: Int?) -> DiscoveredIssue {
        .valid(
            Issue(
                id: github ?? 0, folderName: "\(github ?? 0)-x", title: "t", type: .feature,
                status: .approved, created: Date(timeIntervalSince1970: 0),
                updated: Date(timeIntervalSince1970: 0), branch: "issue/x", labels: [], github: github))
    }

    @Test("archive scan collects github numbers from archived specs, skipping those without")
    func scanArchive() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeArchiveSpec(in: project, folder: "00101-a", github: 101)
        try writeArchiveSpec(in: project, folder: "00102-b", github: 102)
        try writeArchiveSpec(in: project, folder: "00103-c", github: nil)

        let numbers = AdoptedGitHubScan.archivedNumbers(
            inArchive: IssueLayout.archiveDirectory(in: project))
        #expect(numbers == [101, 102])
    }

    @Test("adoptedGitHubNumbers unions active snapshot and archive scan")
    func combinesActiveAndArchive() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeArchiveSpec(in: project, folder: "00101-a", github: 101)

        let model = ProjectKanbanModel()
        model.ingest([], projectURL: project)
        model._setIssuesForTesting([validIssue(github: 200), validIssue(github: nil)])
        await model.refreshAdoptedGitHubNumbers()

        #expect(model.adoptedGitHubNumbers == [101, 200])
    }
}
