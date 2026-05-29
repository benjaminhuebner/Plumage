import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("GitSyncModel")
struct GitSyncModelTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")

    @Test("happy push streams lines then transitions to finished(exit: 0)")
    func happyPush() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "Enumerating objects: 5")),
            .line(GitStreamLine(source: .stdout, text: "To github.com:foo/bar.git")),
            .finished(exitCode: 0),
        ])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner,
            successAutoDismissSeconds: 0.01
        )
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(model.lines.count == 2)
        #expect(model.shouldAutoDismiss)
        #expect(model.didFail == false)
    }

    @Test("failure surfaces exit code and keeps sheet open")
    func failureKeepsOpen() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "error: failed to push some refs")),
            .finished(exitCode: 1),
        ])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner
        )
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(model.didFail)
        #expect(!model.shouldAutoDismiss)
    }

    @Test("auth-prompt flips state to authBlocked and ignores subsequent .finished")
    func authBlockedSticks() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "Username for 'https://github.com':")),
            .authPromptDetected,
            .finished(exitCode: 128),
        ])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner
        )
        model.start()
        await runner.complete()
        try await waitFor(timeout: .seconds(2)) { await model.isAuthBlocked }
        #expect(model.isAuthBlocked)
        #expect(!model.shouldAutoDismiss)
    }

    @Test("retryingWithUpstream marker propagates to model flag")
    func retryFlag() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "no upstream")),
            .retryingWithUpstream(branch: "feature/x"),
            .line(GitStreamLine(source: .stdout, text: "Branch 'feature/x' set up to track 'origin/feature/x'.")),
            .finished(exitCode: 0),
        ])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "feature/x",
            runner: runner,
            successAutoDismissSeconds: 0.01
        )
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)
        #expect(model.didRetryWithUpstream)
    }
}

// MARK: - Helpers

private func waitForFinished(model: GitSyncModel) async throws {
    try await waitFor(timeout: .seconds(2)) {
        await MainActor.run { !model.isRunning }
    }
}

private func waitFor(
    timeout: Duration,
    _ condition: @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition not satisfied in time")
}

// Test runner that emits a scripted sequence on demand. `complete()` waits
// for the consumer task to finish so assertions see the full state.
private final class ScriptedSyncRunner: GitSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private let script: [GitSyncEvent]
    private var completionContinuation: CheckedContinuation<Void, Never>?

    init(script: [GitSyncEvent]) {
        self.script = script
    }

    func run(
        operation: GitSyncOperation,
        repoURL: URL,
        currentBranch: String?
    ) -> AsyncStream<GitSyncEvent> {
        AsyncStream { continuation in
            for event in script { continuation.yield(event) }
            continuation.finish()
            DispatchQueue.global().async { [self] in
                lock.lock()
                let cont = completionContinuation
                completionContinuation = nil
                lock.unlock()
                cont?.resume()
            }
        }
    }

    func complete() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            completionContinuation = cont
            lock.unlock()
        }
        // Yield one extra tick so the model's consume() loop catches up.
        try? await Task.sleep(for: .milliseconds(20))
    }
}
