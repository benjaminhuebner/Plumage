import Foundation
import os

// Teardown that must complete before ⌘Q (flush dirty editors, stop claude
// subprocesses). SwiftUI's .onDisappear is fire-and-forget on app termination,
// so the delegate defers the quit (.terminateLater) until these handlers ran.
@MainActor
final class QuitCoordinator {
    static let shared = QuitCoordinator()

    private static let logger = Logger(subsystem: "com.plumage", category: "QuitCoordinator")

    private var handlers: [UUID: @MainActor () async -> Void] = [:]

    var isEmpty: Bool { handlers.isEmpty }

    func register(_ id: UUID, handler: @escaping @MainActor () async -> Void) {
        handlers[id] = handler
    }

    func unregister(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    // Bounded: a wedged flush must not make ⌘Q hang forever. Task.value
    // ignores the awaiting side's cancellation and handlers need not be
    // cancellation-responsive, so both sides race a resume-once continuation.
    func runAll(timeout: Duration = .seconds(3)) async {
        let pending = Array(handlers.values)
        guard !pending.isEmpty else { return }
        let race = RaceState()
        let work = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for handler in pending {
                    group.addTask { await handler() }
                }
            }
            race.finish()
        }
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            Self.logger.warning(
                "quit handlers timed out after \(timeout.components.seconds, privacy: .public)s — cancelling \(pending.count) handler(s)"
            )
            work.cancel()
            race.finish()
        }
        await withCheckedContinuation { continuation in
            race.attach(continuation)
        }
        watchdog.cancel()
    }
}

// finish() may run before the waiter attaches; the lock makes every
// ordering resume exactly once, like SecurityToolTermination.
private final class RaceState: Sendable {
    private struct State {
        var finished = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func finish() {
        state.withLock { box in
            guard !box.finished else { return }
            box.finished = true
            if let continuation = box.continuation {
                box.continuation = nil
                continuation.resume()
            }
        }
    }

    func attach(_ continuation: CheckedContinuation<Void, Never>) {
        state.withLock { box in
            if box.finished {
                continuation.resume()
            } else {
                box.continuation = continuation
            }
        }
    }
}
