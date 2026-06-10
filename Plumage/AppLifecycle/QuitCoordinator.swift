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

    // Bounded: a wedged flush must not make ⌘Q hang forever — after the
    // timeout the quit proceeds and the remaining work is abandoned.
    func runAll(timeout: Duration = .seconds(3)) async {
        let pending = handlers.values
        let work = Task { @MainActor in
            for handler in pending {
                await handler()
            }
        }
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
        }
        await work.value
        watchdog.cancel()
    }
}
