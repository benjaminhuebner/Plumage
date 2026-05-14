import Foundation

// @unchecked Sendable: backing storage is serialised by an internal NSLock,
// so every access (read or mutate) crosses the lock — safe to pass across
// concurrency domains in tests.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(value: T) {
        stored = value
    }

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
