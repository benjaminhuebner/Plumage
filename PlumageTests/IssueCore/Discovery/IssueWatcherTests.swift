import Testing

@testable import Plumage

@Suite("IssueWatcher (unit)")
struct IssueWatcherTests {
    @Test("burst of raw signals coalesces into a single changed event")
    func burstCoalescesIntoOneChanged() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = IssueWatcher(rawSignals: rawSignals, clock: clock)
        let collector = ChangeCollector()

        let consumer = Task { [events = watcher.events] in
            for await event in events { await collector.record(event) }
        }

        for _ in 0..<5 { rawCont.yield(()) }
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        // The burst coalesced into exactly one debounce waiter (asserted above)
        // which fired once; with no further signal there is no further waiter
        // and no further event, so the count is stably 1 — no settle needed.
        let final = await collector.count
        #expect(final == 1)
        let last = await collector.last
        #expect(last == .changed)

        rawCont.finish()
        consumer.cancel()
        _ = await consumer.value
    }
}

private actor ChangeCollector {
    private(set) var count: Int = 0
    private(set) var last: IssueChangeEvent?
    func record(_ event: IssueChangeEvent) {
        count += 1
        last = event
    }
}
