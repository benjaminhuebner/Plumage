import Foundation
import Testing

@testable import Plumage

@Suite("QuitCoordinator")
@MainActor
struct QuitCoordinatorTests {
    @Test("runAll awaits every registered handler")
    func runsAllHandlers() async {
        let coordinator = QuitCoordinator()
        let ran = LockedBox<Set<Int>>(value: [])
        coordinator.register(UUID()) { ran.mutate { $0.insert(1) } }
        coordinator.register(UUID()) { ran.mutate { $0.insert(2) } }

        await coordinator.runAll(timeout: .seconds(3))

        #expect(ran.value == [1, 2])
    }

    @Test("runAll returns after the timeout even when a handler is wedged")
    func wedgedHandlerDoesNotBlockQuit() async {
        let coordinator = QuitCoordinator()
        let fastRan = LockedBox<Bool>(value: false)
        // Not cancellation-responsive on purpose: a wedged file write doesn't
        // observe Task.isCancelled either.
        coordinator.register(UUID()) {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        coordinator.register(UUID()) { fastRan.mutate { $0 = true } }

        let start = ContinuousClock.now
        // 500 ms, not less: the fast handler must reliably win the race against
        // the watchdog even on a loaded machine.
        await coordinator.runAll(timeout: .milliseconds(500))

        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(fastRan.value)
    }

    @Test("runAll with no handlers returns immediately")
    func emptyRegistryIsNoop() async {
        let coordinator = QuitCoordinator()
        await coordinator.runAll(timeout: .milliseconds(50))
        #expect(coordinator.isEmpty)
    }
}
