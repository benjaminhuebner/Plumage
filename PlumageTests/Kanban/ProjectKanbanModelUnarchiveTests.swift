import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ProjectKanbanModel unarchive")
struct ProjectKanbanModelUnarchiveTests {
    private func issue(_ folder: String) -> DiscoveredIssue {
        .valid(
            Issue(
                id: 1, folderName: folder, title: "t", type: .feature, status: .done,
                created: Date(timeIntervalSince1970: 0), updated: Date(timeIntervalSince1970: 0),
                branch: "issue/\(folder)", labels: []))
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "KanbanUnarchive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".claude/issues"), withIntermediateDirectories: true)
        return root
    }

    private func writeArchived(in project: URL, folder: String) throws {
        let dir = project.appending(path: ".claude/issues/archive/\(folder)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let spec = """
            ---
            id: 1
            title: t
            type: feature
            status: done
            created: 2026-01-01T00:00:00Z
            updated: 2026-01-01T00:00:00Z
            branch: issue/\(folder)
            labels: []
            ---

            Body.
            """
        try spec.write(to: dir.appending(path: "spec.md"), atomically: true, encoding: .utf8)
    }

    @Test("success removes the card and signals completion")
    func optimisticSuccess() async throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        // Only the surviving card is on disk; the unarchived one is faked as moved.
        try writeArchived(in: project, folder: "00002-b")

        let model = ProjectKanbanModel(unarchiver: { _, _ in URL(filePath: "/moved") })
        model._setArchivedIssuesForTesting([issue("00001-a"), issue("00002-b")])

        await model.performUnarchiveOptimistic(folderName: "00001-a", projectURL: project)

        #expect(model.archivedIssues.map(\.id) == ["00002-b"])
        #expect(model.lastRemovalCompleted == "00001-a")
        #expect(model.lastRemovalError == nil)
    }

    @Test("failure rolls the card back and surfaces an error")
    func rollbackOnFailure() async throws {
        struct MoveFailed: Error {}
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let model = ProjectKanbanModel(unarchiver: { _, _ in throw MoveFailed() })
        model._setArchivedIssuesForTesting([issue("00001-a")])

        await model.performUnarchiveOptimistic(folderName: "00001-a", projectURL: project)

        #expect(model.archivedIssues.map(\.id) == ["00001-a"])
        #expect(model.lastRemovalError != nil)
    }
}
