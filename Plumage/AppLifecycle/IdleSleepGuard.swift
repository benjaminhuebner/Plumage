import Foundation

// Injected so the guard's hold/release logic is testable without real power state.
protocol IdleSleepAsserting {
    func begin(reason: String) -> any NSObjectProtocol
    func end(_ token: any NSObjectProtocol)
}

// .idleSystemSleepDisabled stops system idle sleep only — the display can still
// sleep. Additive and harmless if energy settings already prevent sleep.
struct ProcessInfoIdleSleepAsserter: IdleSleepAsserting {
    func begin(reason: String) -> any NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: reason)
    }

    func end(_ token: any NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }
}

// Dropping the guard drops the token, which ends the activity as a safety net.
@MainActor
@Observable
final class IdleSleepGuard {
    private let asserter: any IdleSleepAsserting
    private let reason: String
    private var token: (any NSObjectProtocol)?

    var isHolding: Bool { token != nil }

    init(
        asserter: any IdleSleepAsserting = ProcessInfoIdleSleepAsserter(),
        reason: String = "A Claude session is running"
    ) {
        self.asserter = asserter
        self.reason = reason
    }

    func update(shouldHold: Bool) {
        if shouldHold {
            guard token == nil else { return }
            token = asserter.begin(reason: reason)
        } else {
            guard let held = token else { return }
            asserter.end(held)
            token = nil
        }
    }
}
