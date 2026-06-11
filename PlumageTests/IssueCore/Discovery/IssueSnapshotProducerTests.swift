import Foundation
import Testing

@testable import Plumage

@Suite("IssueSnapshotProducer")
struct IssueSnapshotProducerTests {
    @Test("start() yields the initial discovery snapshot")
    func startYieldsInitialSnapshot() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )
        let collector = SnapshotCollector()

        let consumer = Task { [snapshots = producer.snapshots] in
            for await snapshot in snapshots { await collector.record(snapshot) }
        }
        await producer.start()
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }
        let first = try #require(await collector.last)
        #expect(first.map(\.id) == ["00001-foo"])

        await producer.stop()
        rawCont.finish()
        _ = await consumer.value
    }

    @Test("differing discovery output after a tick yields a new snapshot")
    func tickWithChangedOutputYields() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )
        let collector = SnapshotCollector()

        let consumer = Task { [snapshots = producer.snapshots] in
            for await snapshot in snapshots { await collector.record(snapshot) }
        }

        await producer.start()
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        source.setNext([
            sampleValid(folder: "00001-foo"),
            sampleValid(folder: "00002-bar"),
        ])
        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))

        try await waitUntil(timeout: .seconds(2)) { await collector.count == 2 }
        let second = try #require(await collector.last)
        #expect(second.map(\.id) == ["00001-foo", "00002-bar"])

        await producer.stop()
        rawCont.finish()
        _ = await consumer.value
    }

    @Test("identical discovery output after a tick does not yield again")
    func tickWithIdenticalOutputDoesNotYield() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )
        let collector = SnapshotCollector()

        let consumer = Task { [snapshots = producer.snapshots] in
            for await snapshot in snapshots { await collector.record(snapshot) }
        }
        await producer.start()
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }
        let callsAfterStart = source.callCount

        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))

        try await waitUntil(timeout: .seconds(2)) { source.callCount > callsAfterStart }

        await producer.stop()
        rawCont.finish()
        _ = await consumer.value

        // Identical output after the tick: discovery ran once more, but no new
        // snapshot was yielded. Draining the stream first makes the negative
        // assertion deterministic — a spurious yield would have been counted.
        let count = await collector.count
        #expect(count == 1)
        #expect(source.callCount == callsAfterStart + 1)
    }

    @Test("stop() finishes the snapshots stream")
    func stopFinishesSnapshots() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let source = SnapshotSource(value: [sampleValid(folder: "00001-foo")])
        let producer = IssueSnapshotProducer(
            projectURL: URL(filePath: "/tmp/probe"),
            watcher: watcher,
            discover: source.discover
        )

        await producer.start()
        let consumer = Task { [snapshots = producer.snapshots] () -> String in
            for await _ in snapshots {}
            return "done"
        }
        await producer.stop()
        let result = await consumer.value
        #expect(result == "done")
        rawCont.finish()
    }

    private func sampleValid(folder: String, status: IssueStatus = .approved) -> DiscoveredIssue {
        .valid(
            Plumage.Issue(
                id: 1,
                folderName: folder,
                title: "T",
                type: .feature,
                status: status,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/\(folder)",
                labels: []
            )
        )
    }
}

private actor SnapshotCollector {
    private(set) var snapshots: [[DiscoveredIssue]] = []
    var count: Int { snapshots.count }
    var last: [DiscoveredIssue]? { snapshots.last }
    func record(_ snapshot: [DiscoveredIssue]) { snapshots.append(snapshot) }
}
