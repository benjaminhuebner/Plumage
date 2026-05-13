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

    @Test("consumer task cancellation stops iteration")
    func consumerCancellationStopsIteration() async {
        let clock = ManualClock()
        let debouncer = Debouncer(window: .milliseconds(250), clock: clock)

        let consumer = Task { [events = debouncer.events] () -> String in
            for await _ in events {}
            return "done"
        }
        consumer.cancel()
        let result = await consumer.value
        #expect(result == "done")
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

private struct WaitTimeoutError: Error {}

private func waitUntil(
    timeout: Duration,
    condition: @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw WaitTimeoutError()
}

nonisolated final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    var now: Instant { lock.withLock { Instant(offset: currentOffset) } }
    var minimumResolution: Duration { .zero }

    private let lock = NSLock()
    private var currentOffset: Duration = .zero
    private var waiters: [Int: Waiter] = [:]
    private var nextID: Int = 0

    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let waiterID: Int = lock.withLock {
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                if currentOffset >= deadline.offset {
                    lock.unlock()
                    cont.resume()
                    return
                }
                waiters[waiterID] = Waiter(deadline: deadline.offset, continuation: cont)
                lock.unlock()
            }
        } onCancel: {
            let cancelled: Waiter? = lock.withLock {
                let waiter = waiters[waiterID]
                waiters[waiterID] = nil
                return waiter
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due: [Waiter] = lock.withLock {
            currentOffset += duration
            let satisfied = waiters.filter { $0.value.deadline <= currentOffset }
            for key in satisfied.keys { waiters[key] = nil }
            return Array(satisfied.values)
        }
        for waiter in due {
            waiter.continuation.resume()
        }
    }

    func waitForWaiterCount(_ expected: Int) async throws {
        for _ in 0..<400 {
            let count = lock.withLock { waiters.count }
            if count == expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ManualClockError.timeoutWaitingForWaiters(expected: expected)
    }

    enum ManualClockError: Error {
        case timeoutWaitingForWaiters(expected: Int)
    }
}
