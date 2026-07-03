import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.computeMutation")
struct ComputeMutationTests {
    @Test("drop into different column changes status and clears order")
    func crossColumnDrop() {
        let issue = makeIssue(id: 1, folder: "00001-foo", status: .approved)
        let mutation = ProjectKanbanModel.computeMutation(
            issue: issue,
            target: .column(.inProgress),
            snapshot: [.valid(issue)]
        )
        #expect(mutation == .apply(newStatus: .inProgress, newOrder: .set(nil)))
    }

    @Test("drop into the issue's own column is a no-op")
    func sameColumnNoop() {
        let issue = makeIssue(id: 1, folder: "00001-foo", status: .approved)
        let mutation = ProjectKanbanModel.computeMutation(
            issue: issue,
            target: .column(.todo),
            snapshot: [.valid(issue)]
        )
        #expect(mutation == .noop)
    }

    @Test("reorder within same column above first card uses below.order - 1")
    func reorderInSameColumnAboveFirst() {
        let dragged = makeIssue(id: 3, folder: "00003-c", status: .approved, order: 30)
        let target = makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        let other = makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20)
        let snapshot: [DiscoveredIssue] = [.valid(dragged), .valid(target), .valid(other)]
        let mutation = ProjectKanbanModel.computeMutation(
            issue: dragged,
            target: .aboveCard(folderName: "00001-a", column: .todo),
            snapshot: snapshot
        )
        #expect(mutation == .apply(newStatus: .approved, newOrder: .set(9.0)))
    }

    @Test("reorder within same column below last card uses above.order + 1")
    func reorderInSameColumnBelowLast() {
        let dragged = makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        let mid = makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20)
        let last = makeIssue(id: 3, folder: "00003-c", status: .approved, order: 30)
        let snapshot: [DiscoveredIssue] = [.valid(dragged), .valid(mid), .valid(last)]
        let mutation = ProjectKanbanModel.computeMutation(
            issue: dragged,
            target: .belowCard(folderName: "00003-c", column: .todo),
            snapshot: snapshot
        )
        #expect(mutation == .apply(newStatus: .approved, newOrder: .set(31.0)))
    }

    @Test("reorder between two cards averages their orders")
    func reorderBetweenCards() {
        let dragged = makeIssue(id: 9, folder: "00009-z", status: .inProgress)
        let above = makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        let below = makeIssue(id: 2, folder: "00002-b", status: .approved, order: 20)
        let snapshot: [DiscoveredIssue] = [.valid(dragged), .valid(above), .valid(below)]
        let mutation = ProjectKanbanModel.computeMutation(
            issue: dragged,
            target: .aboveCard(folderName: "00002-b", column: .todo),
            snapshot: snapshot
        )
        #expect(mutation == .apply(newStatus: .approved, newOrder: .set(15.0)))
    }

    @Test("reorder above self is a no-op")
    func reorderAboveSelfNoop() {
        let dragged = makeIssue(id: 1, folder: "00001-a", status: .approved, order: 10)
        let mutation = ProjectKanbanModel.computeMutation(
            issue: dragged,
            target: .aboveCard(folderName: "00001-a", column: .todo),
            snapshot: [.valid(dragged)]
        )
        #expect(mutation == .noop)
    }

    @Test("reorder onto a card not in snapshot is a no-op")
    func reorderUnknownTargetNoop() {
        let dragged = makeIssue(id: 1, folder: "00001-a", status: .approved)
        let mutation = ProjectKanbanModel.computeMutation(
            issue: dragged,
            target: .aboveCard(folderName: "ghost", column: .inProgress),
            snapshot: [.valid(dragged)]
        )
        #expect(mutation == .noop)
    }

    private func makeIssue(
        id: Int,
        folder: String,
        status: IssueStatus,
        order: Double? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id,
            folderName: folder,
            title: "t",
            type: .feature,
            status: status,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/\(folder)",
            labels: [],
            order: order
        )
    }
}

@Suite("ProjectKanbanModel.performDropOptimistic")
@MainActor
struct PerformDropTests {
    @Test("performDropOptimistic calls mutator with computed status and order")
    func callsMutator() async {
        let captured = LockedBox<[(URL, IssueStatus?, SetValue<Double?>)]>(value: [])
        let model = ProjectKanbanModel(mutator: { url, status, order, _ in
            captured.mutate { $0.append((url, status, order)) }
        })
        model._setIssuesForTesting([.valid(makeIssue(id: 1, folder: "00001-a", status: .approved))])
        let projectURL = URL(filePath: "/tmp/probe")
        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a"),
            to: .column(.inProgress),
            projectURL: projectURL
        )
        let calls = captured.value
        #expect(calls.count == 1)
        let expectedURL =
            projectURL
            .appendingPathComponent(".claude/issues")
            .appendingPathComponent("00001-a")
            .appendingPathComponent("spec.md")
        #expect(calls.first?.0 == expectedURL)
        #expect(calls.first?.1 == .inProgress)
        #expect(calls.first?.2 == .set(nil))
    }

    @Test("performDropOptimistic no-op does not call mutator")
    func noopSkipsMutator() async {
        let captured = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in
            captured.mutate { $0 += 1 }
        })
        model._setIssuesForTesting([.valid(makeIssue(id: 1, folder: "00001-a", status: .approved))])
        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a"),
            to: .column(.todo),
            projectURL: URL(filePath: "/tmp/probe")
        )
        #expect(captured.value == 0)
    }

    @Test("performDropOptimistic on missing folder name is silent no-op")
    func missingFolderSilent() async {
        let captured = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in
            captured.mutate { $0 += 1 }
        })
        model._setIssuesForTesting([])
        await model.performDropOptimistic(
            IssueDragPayload(folderName: "ghost"),
            to: .column(.inProgress),
            projectURL: URL(filePath: "/tmp/probe")
        )
        #expect(captured.value == 0)
        #expect(model.lastDropError == nil)
    }

    @Test("mutator error surfaces on lastDropError")
    func errorPath() async {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in throw DummyError() })
        model._setIssuesForTesting([.valid(makeIssue(id: 1, folder: "00001-a", status: .approved))])
        await model.performDropOptimistic(
            IssueDragPayload(folderName: "00001-a"),
            to: .column(.inProgress),
            projectURL: URL(filePath: "/tmp/probe")
        )
        #expect(model.lastDropError == "boom")
    }

    private func makeIssue(
        id: Int, folder: String, status: IssueStatus, order: Double? = nil
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t",
            type: .feature, status: status,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: [], order: order
        )
    }
}
