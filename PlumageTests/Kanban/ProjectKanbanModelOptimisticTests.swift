import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.performDropOptimistic snapshot lifecycle")
@MainActor
struct OptimisticDropTests {
    @Test("optimistic update applies locally before mutator returns")
    func successPathSetsPending() async throws {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let initial = Self.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(initial)])

        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a", currentStatus: .approved),
            to: .column(.inProgress),
            projectURL: URL(filePath: "/tmp/probe")
        )

        #expect(model.pendingDropFolderName == "00001-a")
        #expect(model.pendingDropExpectedStatus == .inProgress)
        #expect(model.lastDropError == nil)
        let match = try #require(model.issues.first(where: { $0.id == "00001-a" }))
        guard case .valid(let updated) = match else {
            Issue.record("expected .valid, got \(match)")
            return
        }
        #expect(updated.status == .inProgress)
    }

    @Test("mutator throw rolls back optimistic update and clears pending")
    func failurePathRolledBack() async throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "disk full" }
        }
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in throw DummyError() })
        let initial = Self.makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        model._setIssuesForTesting([.valid(initial)])

        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a", currentStatus: .approved),
            to: .column(.inProgress),
            projectURL: URL(filePath: "/tmp/probe")
        )

        #expect(model.pendingDropFolderName == nil)
        #expect(model.lastDropError == "disk full")
        let match = try #require(model.issues.first(where: { $0.id == "00001-a" }))
        guard case .valid(let after) = match else {
            Issue.record("expected .valid (rolled back), got \(match)")
            return
        }
        #expect(after.status == .approved)
        #expect(after.order == 10)
    }

    @Test("no-op drop neither updates locally nor sets pending")
    func noopLeavesStateUntouched() async {
        let captured = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in
            captured.mutate { $0 += 1 }
        })
        let initial = Self.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(initial)])

        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a", currentStatus: .approved),
            to: .column(.todo),
            projectURL: URL(filePath: "/tmp/probe")
        )

        #expect(captured.value == 0)
        #expect(model.pendingDropFolderName == nil)
        #expect(model.lastDropError == nil)
    }

    nonisolated static func makeIssue(
        id: Int, folder: String, status: IssueStatus, order: Double? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t",
            type: .feature, status: status,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: [], model: nil, order: order
        )
    }
}

@Suite("ProjectKanbanModel.reconcile")
struct ReconcileTests {
    @Test("no pending returns incoming as-is")
    func noPending() {
        let issue = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(issue)],
            pending: nil
        )
        #expect(result.snapshot.count == 1)
        #expect(result.pendingCleared == false)
    }

    @Test("disk matches expected clears pending")
    func diskMatchesExpected() throws {
        let issue = OptimisticDropTests.makeIssue(
            id: 1, folder: "00001-a", status: .inProgress, order: 15)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(issue)],
            pending: ProjectKanbanModel.PendingDrop(
                folderName: "00001-a",
                expectedStatus: .inProgress,
                expectedOrder: .set(15)
            )
        )
        #expect(result.pendingCleared == true)
        let first = try #require(result.snapshot.first)
        guard case .valid(let after) = first else {
            Issue.record("expected .valid, got \(first)")
            return
        }
        #expect(after.status == .inProgress)
        #expect(after.order == 15)
    }

    @Test("pre-write disk content keeps pending and patches snapshot")
    func preWriteContentKeepsPending() throws {
        let issue = OptimisticDropTests.makeIssue(
            id: 1, folder: "00001-a", status: .approved, order: 10)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(issue)],
            pending: ProjectKanbanModel.PendingDrop(
                folderName: "00001-a",
                expectedStatus: .inProgress,
                expectedOrder: .set(20)
            )
        )
        #expect(result.pendingCleared == false)
        let first = try #require(result.snapshot.first)
        guard case .valid(let patched) = first else {
            Issue.record("expected patched .valid, got \(first)")
            return
        }
        #expect(patched.status == .inProgress)
        #expect(patched.order == 20)
    }

    @Test("pending issue absent from disk clears pending")
    func pendingDisappeared() {
        let other = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(other)],
            pending: ProjectKanbanModel.PendingDrop(
                folderName: "00001-a",
                expectedStatus: .inProgress,
                expectedOrder: .set(20)
            )
        )
        #expect(result.pendingCleared == true)
        #expect(result.snapshot.count == 1)
    }

    @Test("pending becomes invalid keeps pending")
    func pendingBecomeInvalid() {
        let result = ProjectKanbanModel.reconcile(
            incoming: [
                .invalid(
                    folder: URL(filePath: "/tmp/00001-a"),
                    error: .invalidEnumValue(field: "status", value: "????")
                )
            ],
            pending: ProjectKanbanModel.PendingDrop(
                folderName: "00001-a",
                expectedStatus: .inProgress,
                expectedOrder: .set(20)
            )
        )
        #expect(result.pendingCleared == false)
    }

    // Guarantees that .invalid entries for issues OTHER than the pending
    // one survive reconcile untouched. Without this, a future change to
    // reconcile that drops or rewrites unrelated invalid entries would
    // pass every other test in this suite.
    @Test("unrelated invalid entries pass through alongside a pending valid match")
    func unrelatedInvalidPassThrough() throws {
        let pending = OptimisticDropTests.makeIssue(
            id: 1, folder: "00001-a", status: .inProgress, order: 15)
        let otherInvalidURL = URL(filePath: "/tmp/00099-z")
        let result = ProjectKanbanModel.reconcile(
            incoming: [
                .valid(pending),
                .invalid(
                    folder: otherInvalidURL,
                    error: .invalidEnumValue(field: "type", value: "ghost")
                ),
            ],
            pending: ProjectKanbanModel.PendingDrop(
                folderName: "00001-a",
                expectedStatus: .inProgress,
                expectedOrder: .set(15)
            )
        )
        #expect(result.pendingCleared == true)
        #expect(result.snapshot.count == 2)
        let invalid = try #require(result.snapshot.last)
        guard case .invalid(let folder, _) = invalid else {
            Issue.record("expected pass-through .invalid, got \(invalid)")
            return
        }
        #expect(folder == otherInvalidURL)
    }
}
