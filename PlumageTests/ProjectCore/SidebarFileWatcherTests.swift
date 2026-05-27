import Foundation
import Testing

@testable import Plumage

@Suite("SidebarFileWatcher (unit)")
struct SidebarFileWatcherTests {
    @Test("burst of raw signals coalesces into a single changed event")
    func burstCoalescesIntoOneChanged() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let watcher = SidebarFileWatcher(rawSignals: rawSignals, clock: clock)
        let collector = ChangeCollector()

        let consumer = Task { [events = watcher.events] in
            for await event in events { await collector.record(event) }
        }

        for _ in 0..<5 { rawCont.yield(()) }
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        clock.advance(by: .milliseconds(500))
        try? await Task.sleep(for: .milliseconds(50))
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
    private(set) var last: SidebarFileChangeEvent?
    func record(_ event: SidebarFileChangeEvent) {
        count += 1
        last = event
    }
}
