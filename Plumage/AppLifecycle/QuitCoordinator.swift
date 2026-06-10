import Foundation

// App-wide registry of teardown work that must complete before ⌘Q finishes:
// flushing dirty editor buffers and stopping claude subprocesses. SwiftUI's
// .onDisappear is fire-and-forget on app termination, so the delegate defers
// the quit (.terminateLater) until these handlers have run.
@MainActor
final class QuitCoordinator {
    static let shared = QuitCoordinator()

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
            work.cancel()
            race.finish()
        }
        // Installed before either MainActor task body can run finish().
        await withCheckedContinuation { continuation in
            race.continuation = continuation
        }
        watchdog.cancel()
    }
}

@MainActor
private final class RaceState {
    var continuation: CheckedContinuation<Void, Never>?

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
