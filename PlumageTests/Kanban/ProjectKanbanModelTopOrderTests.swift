import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.columnEntryOrders")
struct ColumnEntryOrdersTests {
    @Test("external status flip into a populated column writes top order")
    func externalFlipWritesTop() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .waitingForReview)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done, order: 5)),
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done, order: 5)),
        ]
        let writes = ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming)
        #expect(writes.count == 1)
        #expect(writes.first?.folderName == "00001-a")
        #expect(writes.first?.order == 4.0)
    }

    @Test("identical snapshots produce no writes")
    func noStatusChangeNoWrites() {
        let snapshot: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done, order: 4)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done, order: 5)),
        ]
        let writes = ProjectKanbanModel.columnEntryOrders(previous: snapshot, incoming: snapshot)
        #expect(writes.isEmpty)
    }

    @Test("first snapshot produces no writes")
    func firstSnapshotNoWrites() {
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done))
        ]
        #expect(ProjectKanbanModel.columnEntryOrders(previous: [], incoming: incoming).isEmpty)
    }

    @Test("a brand-new issue is not a column entry")
    func newIssueNoWrite() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done, order: 5))
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done, order: 5)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done)),
        ]
        #expect(ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming).isEmpty)
    }

    @Test("status flip inside the same column produces no write")
    func sameColumnFlipNoWrite() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .draft)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .approved, order: 3)),
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .approved)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .approved, order: 3)),
        ]
        #expect(ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming).isEmpty)
    }

    @Test("entering an empty column produces no write")
    func emptyColumnNoWrite() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .waitingForReview))
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done))
        ]
        #expect(ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming).isEmpty)
    }

    @Test("an entrant already sorting on top is not rewritten")
    func alreadyAtTopSkips() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .waitingForReview)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done, order: 5)),
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done, order: 4)),
            .valid(makeIssue(id: 2, folder: "00002-b", status: .done, order: 5)),
        ]
        #expect(ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming).isEmpty)
    }

    @Test("multiple entrants get distinct orders above the column")
    func multiEntryStrictlyOrdered() throws {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 2, folder: "00002-a", status: .inProgress)),
            .valid(makeIssue(id: 3, folder: "00003-b", status: .approved)),
            .valid(makeIssue(id: 9, folder: "00009-c", status: .done, order: 10)),
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 2, folder: "00002-a", status: .done)),
            .valid(makeIssue(id: 3, folder: "00003-b", status: .done)),
            .valid(makeIssue(id: 9, folder: "00009-c", status: .done, order: 10)),
        ]
        let writes = ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming)
        let byFolder = Dictionary(uniqueKeysWithValues: writes.map { ($0.folderName, $0.order) })
        #expect(writes.count == 2)
        let first = try #require(byFolder["00002-a"])
        let second = try #require(byFolder["00003-b"])
        #expect(first < second)
        #expect(second < 10.0)
    }

    @Test("ID fallback of existing cards anchors the top order")
    func idFallbackAnchor() {
        let previous: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .approved)),
            .valid(makeIssue(id: 7, folder: "00007-b", status: .done)),
        ]
        let incoming: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", status: .done)),
            .valid(makeIssue(id: 7, folder: "00007-b", status: .done)),
        ]
        let writes = ProjectKanbanModel.columnEntryOrders(previous: previous, incoming: incoming)
        #expect(writes.count == 1)
        #expect(writes.first?.order == 6.0)
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

@Suite("ProjectKanbanModel top-order observer")
@MainActor
struct ProjectKanbanModelTopOrderObserverTests {
    @Test("external transition writes top order through the mutator")
    func externalTransitionWrites() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [
            Self.discovered(id: 1, folder: "00001-a", status: .waitingForReview),
            Self.discovered(id: 2, folder: "00002-b", status: .done, order: 5),
        ])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )
        let captured = LockedBox<[(URL, IssueStatus?, SetValue<Double?>)]>(value: [])
        let model = ProjectKanbanModel(
            producerFactory: { _ in producer },
            mutator: { url, status, order, _ in
                captured.mutate { $0.append((url, status, order)) }
            }
        )
        let projectURL = URL(filePath: "/tmp/probe")
        let runTask = Task { await model.run(projectURL: projectURL) }

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 2 }
        }
        #expect(captured.value.isEmpty)

        source.setNext([
            Self.discovered(id: 1, folder: "00001-a", status: .done),
            Self.discovered(id: 2, folder: "00002-b", status: .done, order: 5),
        ])
        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))

        try await waitUntil(timeout: .seconds(2)) { captured.value.count == 1 }
        let call = try #require(captured.value.first)
        let expectedURL = IssueLayout.specURL(in: projectURL, folderName: "00001-a")
        #expect(call.0 == expectedURL)
        #expect(call.1 == nil)
        #expect(call.2 == .set(4.0))

        runTask.cancel()
        _ = await runTask.value
        rawCont.finish()
    }

    @Test("a failing top-order write is non-fatal and surfaces no banner")
    func writeFailureNonFatal() async throws {
        struct DummyError: Error {}
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [
            Self.discovered(id: 1, folder: "00001-a", status: .waitingForReview),
            Self.discovered(id: 2, folder: "00002-b", status: .done, order: 5),
        ])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )
        let attempts = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(
            producerFactory: { _ in producer },
            mutator: { _, _, _, _ in
                attempts.mutate { $0 += 1 }
                throw DummyError()
            }
        )
        let runTask = Task { await model.run(projectURL: URL(filePath: "/tmp/probe")) }

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 2 }
        }

        source.setNext([
            Self.discovered(id: 1, folder: "00001-a", status: .done),
            Self.discovered(id: 2, folder: "00002-b", status: .done, order: 5),
        ])
        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))

        try await waitUntil(timeout: .seconds(2)) { attempts.value == 1 }
        await MainActor.run {
            #expect(model.lastDropError == nil)
            #expect(model.issues.count == 2)
        }

        runTask.cancel()
        _ = await runTask.value
        rawCont.finish()
    }

    private static func discovered(
        id: Int, folder: String, status: IssueStatus, order: Double? = nil
    ) -> DiscoveredIssue {
        .valid(
            Plumage.Issue(
                id: id, folderName: folder, title: "t",
                type: .feature, status: status,
                created: .distantPast, updated: .distantPast,
                branch: "issue/\(folder)", labels: [], order: order
            )
        )
    }
}
