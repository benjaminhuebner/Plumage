import Dispatch
import Foundation

// Lock manipulation lives in sync helpers because holding NSCondition
// across an await is a Swift 6 hard error.
final class AsyncGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingSignals: Int = 0
    private var asyncContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { cont in
            if tryConsumeOrEnqueue(cont) {
                cont.resume()
            }
        }
    }

    func waitSync() {
        condition.lock()
        defer { condition.unlock() }
        while pendingSignals == 0 {
            condition.wait()
        }
        pendingSignals -= 1
    }

    func signal() {
        let resumed = popOrIncrement()
        resumed?.resume()
    }

    private func tryConsumeOrEnqueue(_ cont: CheckedContinuation<Void, Never>) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if pendingSignals > 0 {
            pendingSignals -= 1
            return true
        }
        asyncContinuations.append(cont)
        return false
    }

    private func popOrIncrement() -> CheckedContinuation<Void, Never>? {
        condition.lock()
        defer { condition.unlock() }
        if !asyncContinuations.isEmpty {
            return asyncContinuations.removeFirst()
        }
        pendingSignals += 1
        condition.signal()
        return nil
    }
}
