import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel")
@MainActor
struct ProjectKanbanModelTests {
    @Test("single snapshot push assigns to model.issues")
    func singleSnapshotAssigns() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [Self.sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )

        let model = ProjectKanbanModel(producerFactory: { _ in producer })
        let runTask = Task { await model.run(projectURL: URL(filePath: "/tmp/probe")) }

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 1 }
        }
        await MainActor.run {
            #expect(model.issues.map(\.id) == ["00001-foo"])
        }

        runTask.cancel()
        _ = await runTask.value
        rawCont.finish()
    }

    @Test("the last of several pushed snapshots wins")
    func multipleSnapshotsLastWins() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [Self.sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )

        let model = ProjectKanbanModel(producerFactory: { _ in producer })
        let runTask = Task { await model.run(projectURL: URL(filePath: "/tmp/probe")) }

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 1 }
        }

        source.setNext([
            Self.sampleValid(folder: "00001-foo"),
            Self.sampleValid(folder: "00002-bar"),
        ])
        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 2 }
        }
        await MainActor.run {
            #expect(model.issues.map(\.id) == ["00001-foo", "00002-bar"])
        }

        runTask.cancel()
        _ = await runTask.value
        rawCont.finish()
    }

    @Test("cancelling the run task stops the producer via onCancel")
    func cancellationStopsProducer() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [Self.sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )

        let model = ProjectKanbanModel(producerFactory: { _ in producer })
        let runTask = Task { await model.run(projectURL: URL(filePath: "/tmp/probe")) }

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.issues.count == 1 }
        }

        runTask.cancel()
        _ = await runTask.value

        try await waitUntil(timeout: .seconds(2)) { await producer.hasStopped }
        rawCont.finish()
    }

    private static func sampleValid(folder: String) -> DiscoveredIssue {
        .valid(
            Plumage.Issue(
                id: 1,
                folder: folder,
                title: "T",
                type: .feature,
                status: .approved,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/\(folder)",
                labels: [],
                model: nil
            )
        )
    }
}
