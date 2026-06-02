import Foundation
import Observation

@Observable
@MainActor
final class GitSyncModel {
    enum RunState: Sendable, Equatable {
        case idle
        case running
        case authBlocked
        case finished(exitCode: Int32)
    }

    let repoURL: URL
    let operation: GitSyncOperation
    let currentBranch: String?

    private(set) var lines: [GitStreamLine] = []
    private(set) var state: RunState = .idle
    private(set) var didRetryWithUpstream = false

    private let runner: any GitSyncing

    @ObservationIgnored private var runTask: Task<Void, Never>?
    // Auto-dismiss delay after a successful exit; surfaced so a test can
    // verify the timing if it needs to. 1.0 s lets the user see the final
    // line + a confirmation tick before the sheet collapses.
    @ObservationIgnored let successAutoDismissSeconds: Double

    init(
        repoURL: URL,
        operation: GitSyncOperation,
        currentBranch: String?,
        runner: any GitSyncing = GitSyncRunner(),
        successAutoDismissSeconds: Double = 1.0
    ) {
        self.repoURL = repoURL
        self.operation = operation
        self.currentBranch = currentBranch
        self.runner = runner
        self.successAutoDismissSeconds = successAutoDismissSeconds
    }

    // Safety net for abnormal sheet teardown (Escape / system-initiated close)
    // where the view's .onDisappear → cancel() is skipped. Otherwise an
    // in-flight push/pull keeps the runner + stream alive until it finishes.
    isolated deinit {
        runTask?.cancel()
    }

    var headerTitle: String { operation.displayName }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var shouldAutoDismiss: Bool {
        if case .finished(let exit) = state { return exit == 0 && !isAuthBlocked }
        return false
    }

    var isAuthBlocked: Bool {
        if case .authBlocked = state { return true }
        return false
    }

    func waitForAutoDismiss() async -> Bool {
        guard shouldAutoDismiss else { return false }
        try? await Task.sleep(for: .seconds(successAutoDismissSeconds))
        return shouldAutoDismiss
    }

    var didFail: Bool {
        if case .finished(let exit) = state { return exit != 0 }
        return false
    }

    func start() {
        guard runTask == nil else { return }  // singleton-guard for menu-spam
        state = .running
        lines.removeAll()
        runTask = Task {
            let stream = runner.run(
                operation: operation, repoURL: repoURL, currentBranch: currentBranch)
            for await event in stream {
                if Task.isCancelled { break }
                consume(event)
            }
            // If the loop exited without a .finished event (cancel-mid-flight),
            // close out the state so the view doesn't get stuck on "running".
            if case .running = state { state = .finished(exitCode: -1) }
            runTask = nil
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func consume(_ event: GitSyncEvent) {
        switch event {
        case .line(let line):
            lines.append(line)
        case .retryingWithUpstream:
            didRetryWithUpstream = true
        case .authPromptDetected:
            // Stay in `.authBlocked` so the sheet sticks around with the
            // explanatory banner — even if the underlying process exits with
            // a non-zero code afterward, .finished should NOT collapse the
            // sheet automatically.
            state = .authBlocked
        case .finished(let exit):
            // Auth-blocked sticks; non-auth finishes update the exit code.
            if case .authBlocked = state {
                return
            }
            state = .finished(exitCode: exit)
        }
    }
}
