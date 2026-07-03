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
            IssueDragPayload(folderName: "00007-x"),
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

    @Test("dropping above a peer row computes a midOrder reorder, preserves status")
    func reorderAboveKeepsStatus() async throws {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let first = Self.makeIssue(id: 1, folder: "00001-a", status: .draft, order: 10)
        let second = Self.makeIssue(id: 2, folder: "00002-b", status: .draft, order: 20)
        let third = Self.makeIssue(id: 3, folder: "00003-c", status: .draft, order: 30)
        model._setIssuesForTesting([.valid(first), .valid(second), .valid(third)])

        model.applyOptimisticDrop(
            IssueDragPayload(folderName: "00003-c"),
            to: .aboveCard(folderName: "00002-b", column: .todo),
            projectURL: URL(filePath: "/tmp/probe")
        )

        let match = try #require(model.issues.first(where: { $0.id == "00003-c" }))
        guard case .valid(let updated) = match else {
            Issue.record("expected valid")
            return
        }
        #expect(updated.status == .draft)
        let newOrder = try #require(updated.order)
        #expect(newOrder > 10 && newOrder < 20)
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
            IssueDragPayload(folderName: "00007-x"),
            to: .column(.todo),
            projectURL: URL(filePath: "/tmp/probe")
        )

        #expect(calls.value == 0)
        #expect(model.pendingDropFolderName == nil)
    }

    nonisolated static func makeIssue(
        id: Int, folder: String, status: IssueStatus, order: Double? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t", type: .feature, status: status,
            created: .distantPast, updated: .distantPast, branch: "issue/\(folder)",
            labels: [], order: order
        )
    }
}
