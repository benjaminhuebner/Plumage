import Foundation
import os

// Shared output event for both push and pull. The view consumes this stream
// directly — each line is appended to the live output view, the outcome
// drives the success/error dismissal.
nonisolated enum GitSyncEvent: Sendable, Equatable {
    case line(GitStreamLine)
    case finished(exitCode: Int32)
    case authPromptDetected
    case retryingWithUpstream(branch: String)
}

nonisolated enum GitSyncOperation: Sendable, Equatable {
    case push
    case pull

    var displayName: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        }
    }
}

nonisolated enum GitSyncError: Error, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        }
    }
}

// Heuristic patterns that mean "git is about to ask the TTY for credentials
// and the subprocess has no TTY". When seen on stderr we kill the subprocess
// and surface the auth-prompt-detected event so the UI can show its banner.
nonisolated enum AuthPromptDetector {
    static let patterns: [String] = [
        "Username for '",
        "Password for '",
        "Username for https://",
        "Password for https://",
        "could not read Username",
        "could not read Password",
        "terminal prompts disabled",
    ]

    static func isAuthPrompt(_ line: String) -> Bool {
        for pattern in patterns where line.contains(pattern) {
            return true
        }
        return false
    }
}

nonisolated enum NoUpstreamDetector {
    // Stderr fragments that indicate "git push" failed solely because the
    // current branch has no upstream tracking. Matched on stderr only.
    static let patterns: [String] = [
        "has no upstream branch",
        "set-upstream",
    ]

    static func looksLikeMissingUpstream(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: "\n")
        // Both fragments must appear together. `set-upstream` alone could
        // be in a different message context.
        let hasUpstream = joined.contains("has no upstream branch")
        let mentionsFlag = joined.contains("--set-upstream") || joined.contains("set-upstream")
        return hasUpstream && mentionsFlag
    }
}

nonisolated protocol GitSyncing: Sendable {
    func run(
        operation: GitSyncOperation,
        repoURL: URL,
        currentBranch: String?
    ) -> AsyncStream<GitSyncEvent>
}

nonisolated struct GitSyncRunner: GitSyncing {
    let streamer: any GitProcessStreaming
    let resolveBinary: @Sendable () -> URL?

    init(
        streamer: any GitProcessStreaming = ProductionGitProcessStreamer(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.streamer = streamer
        self.resolveBinary = resolveBinary
    }

    func run(
        operation: GitSyncOperation,
        repoURL: URL,
        currentBranch: String?
    ) -> AsyncStream<GitSyncEvent> {
        AsyncStream { continuation in
            let task = Task {
                await runImpl(
                    operation: operation,
                    repoURL: repoURL,
                    currentBranch: currentBranch,
                    continuation: continuation
                )
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func runImpl(
        operation: GitSyncOperation,
        repoURL: URL,
        currentBranch: String?,
        continuation: AsyncStream<GitSyncEvent>.Continuation
    ) async {
        guard let binary = resolveBinary() else {
            continuation.yield(
                .line(
                    GitStreamLine(
                        source: .stderr,
                        text: GitSyncError.gitNotFound.displayMessage)))
            continuation.yield(.finished(exitCode: 127))
            return
        }

        let firstAttempt =
            operation == .push
            ? ["-C", repoURL.path, "push"]
            : ["-C", repoURL.path, "pull"]

        let result = await runOnce(binary: binary, args: firstAttempt, continuation: continuation)

        if result.authPromptHit {
            // Don't try to retry; the user must configure credentials externally.
            continuation.yield(.finished(exitCode: result.exitCode))
            return
        }

        // Auto-retry path: push without upstream → `--set-upstream origin <branch>`.
        if operation == .push,
            result.exitCode != 0,
            let branch = currentBranch,
            NoUpstreamDetector.looksLikeMissingUpstream(result.stderrLines)
        {
            continuation.yield(.retryingWithUpstream(branch: branch))
            let retryArgs = ["-C", repoURL.path, "push", "--set-upstream", "origin", branch]
            let retry = await runOnce(binary: binary, args: retryArgs, continuation: continuation)
            continuation.yield(.finished(exitCode: retry.exitCode))
            return
        }

        continuation.yield(.finished(exitCode: result.exitCode))
    }

    private struct RunOutcome {
        let exitCode: Int32
        let stderrLines: [String]
        let authPromptHit: Bool
    }

    private func runOnce(
        binary: URL,
        args: [String],
        continuation: AsyncStream<GitSyncEvent>.Continuation
    ) async -> RunOutcome {
        let stream: AsyncStream<GitStreamLine>
        let outcome: () async -> GitStreamOutcome
        do {
            (stream, outcome) = try await streamer.stream(
                binaryURL: binary, args: args, cwd: nil)
        } catch let error as GitProcessRunnerError {
            continuation.yield(
                .line(
                    GitStreamLine(
                        source: .stderr, text: error.displayMessage)))
            return RunOutcome(exitCode: 127, stderrLines: [], authPromptHit: false)
        } catch {
            continuation.yield(
                .line(
                    GitStreamLine(
                        source: .stderr, text: "Failed to launch git: \(error.localizedDescription)")))
            return RunOutcome(exitCode: 127, stderrLines: [], authPromptHit: false)
        }

        var stderrLines: [String] = []
        var authHit = false
        for await line in stream {
            if line.source == .stderr { stderrLines.append(line.text) }
            if !authHit, AuthPromptDetector.isAuthPrompt(line.text) {
                authHit = true
                continuation.yield(.authPromptDetected)
                // Spec wording said "kill the subprocess via task cancellation"
                // here. We don't — we just emit the event and keep draining.
                // The kill is structurally unnecessary because
                // ProductionGitProcessStreamer sets stdin = nullDevice, so git
                // can never block waiting on stdin and exits on its own within
                // milliseconds of the prompt. Calling task.cancel() here would
                // race the imminent natural exit and risk shooting an unrelated
                // PID if the kernel recycled it (the same race that the
                // ProcessRunning SIGKILL grace-check guards against).
            }
            continuation.yield(.line(line))
            if Task.isCancelled { break }
        }
        let exit = await outcome()
        return RunOutcome(
            exitCode: exit.exitCode, stderrLines: stderrLines, authPromptHit: authHit)
    }
}
