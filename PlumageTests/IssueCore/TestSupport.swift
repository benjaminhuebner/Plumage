import Foundation

@testable import Plumage

final class SnapshotSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [DiscoveredIssue]
    private var calls: Int = 0

    init(value: [DiscoveredIssue]) {
        self.value = value
    }

    func setNext(_ snapshot: [DiscoveredIssue]) {
        lock.lock()
        defer { lock.unlock() }
        value = snapshot
    }

    var callCount: Int { lock.withLock { calls } }

    var discover: @Sendable (URL) -> [DiscoveredIssue] {
        { [self] _ in
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return value
        }
    }
}
