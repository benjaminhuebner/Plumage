import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.performDropOptimistic snapshot lifecycle")
@MainActor
struct OptimisticDropTests {
    @Test("optimistic update applies locally before mutator returns")
    func successPathSetsPending() async {
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
        if case .valid(let updated) = model.issues.first(where: { $0.id == "00001-a" }) {
            #expect(updated.status == .inProgress)
        } else {
            #expect(Bool(false), "expected optimistic update to keep issue valid")
        }
    }

    @Test("mutator throw rolls back optimistic update and clears pending")
    func failurePathRolledBack() async {
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
        if case .valid(let after) = model.issues.first(where: { $0.id == "00001-a" }) {
            #expect(after.status == .approved)
            #expect(after.order == 10)
        } else {
            #expect(Bool(false), "expected rollback to restore valid issue")
        }
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
            pending: nil,
            expectedStatus: nil,
            expectedOrder: nil
        )
        #expect(result.snapshot.count == 1)
        #expect(result.pendingCleared == false)
    }

    @Test("disk matches expected clears pending")
    func diskMatchesExpected() {
        let issue = OptimisticDropTests.makeIssue(
            id: 1, folder: "00001-a", status: .inProgress, order: 15)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(issue)],
            pending: "00001-a",
            expectedStatus: .inProgress,
            expectedOrder: .set(15)
        )
        #expect(result.pendingCleared == true)
        if case .valid(let after) = result.snapshot.first {
            #expect(after.status == .inProgress)
            #expect(after.order == 15)
        }
    }

    @Test("pre-write disk content keeps pending and patches snapshot")
    func preWriteContentKeepsPending() {
        let issue = OptimisticDropTests.makeIssue(
            id: 1, folder: "00001-a", status: .approved, order: 10)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(issue)],
            pending: "00001-a",
            expectedStatus: .inProgress,
            expectedOrder: .set(20)
        )
        #expect(result.pendingCleared == false)
        if case .valid(let patched) = result.snapshot.first {
            #expect(patched.status == .inProgress)
            #expect(patched.order == 20)
        } else {
            #expect(Bool(false), "expected patched valid entry")
        }
    }

    @Test("pending issue absent from disk clears pending")
    func pendingDisappeared() {
        let other = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        let result = ProjectKanbanModel.reconcile(
            incoming: [.valid(other)],
            pending: "00001-a",
            expectedStatus: .inProgress,
            expectedOrder: .set(20)
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
            pending: "00001-a",
            expectedStatus: .inProgress,
            expectedOrder: .set(20)
        )
        #expect(result.pendingCleared == false)
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(value: T) { stored = value }
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func mutate(_ block: (inout T) -> Void) {
        lock.lock()
        block(&stored)
        lock.unlock()
    }
}
