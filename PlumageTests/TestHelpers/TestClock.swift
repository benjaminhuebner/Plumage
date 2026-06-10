import Foundation

// @unchecked Sendable: every mutable member (currentOffset, waiters, nextID) is
// accessed only under `lock` (NSLock).
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
        try await waitUntil(timeout: .seconds(2)) { [self] in
            lock.withLock { waiters.count } == expected
        }
    }
}
