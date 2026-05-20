import Foundation
import Testing

@testable import Plumage

@Suite("Sidebar issue drag → kanban applyOptimisticDrop")
@MainActor
struct SidebarIssueDragTests {
    @Test("dropping across status columns flips status optimistically")
    func statusRoundtrip() async throws {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let issue = Self.makeIssue(id: 7, folder: "00007-x", status: .draft)
        model._setIssuesForTesting([.valid(issue)])

        model.applyOptimisticDrop(
            IssueDragPayload(folderName: "00007-x", currentStatus: .draft),
            to: .column(.inProgress),
            projectURL: URL(filePath: "/tmp/probe")
        )

        let match = try #require(model.issues.first(where: { $0.id == "00007-x" }))
        guard case .valid(let after) = match else {
            Issue.record("expected valid")
            return
        }
        #expect(after.status == .inProgress)
        #expect(model.pendingDropExpectedStatus == .inProgress)
    }

    @Test("dropping into source column is a no-op (no mutator call)")
    func sameColumnIsNoOp() async {
        let calls = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in
            calls.mutate { $0 += 1 }
        })
        let issue = Self.makeIssue(id: 7, folder: "00007-x", status: .draft)
        model._setIssuesForTesting([.valid(issue)])

        model.applyOptimisticDrop(
            IssueDragPayload(folderName: "00007-x", currentStatus: .draft),
            to: .column(.todo),
            projectURL: URL(filePath: "/tmp/probe")
        )

        #expect(calls.value == 0)
        #expect(model.pendingDropFolderName == nil)
    }

    nonisolated static func makeIssue(
        id: Int, folder: String, status: IssueStatus
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t", type: .feature, status: status,
            created: .distantPast, updated: .distantPast, branch: "issue/\(folder)",
            labels: [], model: nil, order: nil
        )
    }
}
