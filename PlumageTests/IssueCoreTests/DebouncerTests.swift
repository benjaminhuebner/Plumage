import Foundation
import Testing

@testable import Plumage

@Suite("Debouncer")
struct DebouncerTests {
    @Test("five signals within window coalesce to one event")
    func fiveSignalsCoalesce() async throws {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)
        let collector = EventCollector()

        let consumer = Task { [events = debouncer.events] in
            for await _ in events { await collector.increment() }
        }

        for _ in 0..<5 { await debouncer.signal() }
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        clock.advance(by: .milliseconds(500))
        try? await Task.sleep(for: .milliseconds(50))
        let final = await collector.count
        #expect(final == 1)

        await debouncer.finish()
        await consumer.value
    }

    @Test("one signal then advance past window yields one event")
    func oneSignalYieldsOne() async throws {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)
        let collector = EventCollector()

        let consumer = Task { [events = debouncer.events] in
            for await _ in events { await collector.increment() }
        }

        await debouncer.signal()
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        await debouncer.finish()
        await consumer.value
    }

    @Test("two signals separated by full window yield two events")
    func twoSpacedSignalsYieldTwo() async throws {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)
        let collector = EventCollector()

        let consumer = Task { [events = debouncer.events] in
            for await _ in events { await collector.increment() }
        }

        await debouncer.signal()
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        await debouncer.signal()
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 2 }

        await debouncer.finish()
        await consumer.value
    }

    @Test("signal arriving after consumer cancel delivers no event")
    func cancelledConsumerReceivesNoEvent() async throws {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)
        let collector = EventCollector()

        let consumer = Task { [events = debouncer.events] in
            for await _ in events { await collector.increment() }
        }
        consumer.cancel()
        _ = await consumer.value

        await debouncer.signal()
        // Advance well past the debounce window; nothing should reach the
        // already-terminated consumer.
        clock.advance(by: .milliseconds(500))
        try? await Task.sleep(for: .milliseconds(50))

        let count = await collector.count
        #expect(count == 0)
        await debouncer.finish()
    }

    @Test("finish during a pending debounce yields no event")
    func finishCancelsPending() async throws {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)
        let collector = EventCollector()

        let consumer = Task { [events = debouncer.events] in
            for await _ in events { await collector.increment() }
        }

        await debouncer.signal()
        try await clock.waitForWaiterCount(1)
        await debouncer.finish()
        clock.advance(by: .milliseconds(500))
        await consumer.value

        let count = await collector.count
        #expect(count == 0)
    }
}

private actor EventCollector {
    private(set) var count: Int = 0
    func increment() { count += 1 }
}
