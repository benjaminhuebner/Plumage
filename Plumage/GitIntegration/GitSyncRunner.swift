import Foundation

// Shared output event for both push and pull. The view consumes this stream
// directly — each line is appended to the live output view, the outcome
// drives the success/error dismissal.
nonisolated enum GitSyncEvent: Sendable, Equatable {
    case line(GitStreamLine)
    case finished(exitCode: Int32)
    case authPromptDetected
    case retryingWithUpstream(branch: String)
    case credentialRejected(login: String)
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

// Per-push configuration chosen in the sync sheet. Ignored for pull.
nonisolated struct GitPushOptions: Sendable, Equatable {
    var remote: String
    var includeTags: Bool
    var force: Bool

    static let `default` = GitPushOptions(remote: "origin", includeTags: false, force: false)

    // Flags emitted right after `push`, in a stable order. force → --force-with-lease
    // (refuses to overwrite if the remote moved since the last fetch); tags →
    // --follow-tags (pushes the branch plus the annotated tags reachable from it).
    var pushFlags: [String] {
        var flags: [String] = []
        if force { flags.append("--force-with-lease") }
        if includeTags { flags.append("--follow-tags") }
        return flags
    }
}

nonisolated enum GitSyncError: LocalizedError, Sendable, Equatable {
    case gitNotFound

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
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

// Server rejected an injected credential (expired/invalid token or no push
// access) — distinct from AuthPromptDetector, which fires when no credential
// was supplied at all.
nonisolated enum PushAuthFailureDetector {
    static let patterns: [String] = [
        "Authentication failed",
        "Invalid username or password",
        "Invalid username or token",
        "Support for password authentication was removed",
        "Password authentication is not supported",
        "401 Unauthorized",
        "403 Forbidden",
        "remote: Permission to",
    ]

    static func looksLikeAuthFailure(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: "\n")
        return patterns.contains { joined.contains($0) }
    }
}

nonisolated enum NoUpstreamDetector {
    // Detects "git push" failing solely because the current branch has no
    // upstream tracking. Matched on stderr only.
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
        currentBranch: String?,
        credential: GitPushCredential?,
        pushOptions: GitPushOptions
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
        currentBranch: String?,
        credential: GitPushCredential? = nil,
        pushOptions: GitPushOptions = .default
    ) -> AsyncStream<GitSyncEvent> {
        AsyncStream { continuation in
            let task = Task {
                await runImpl(
                    operation: operation,
                    repoURL: repoURL,
                    currentBranch: currentBranch,
                    credential: credential,
                    pushOptions: pushOptions,
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
        credential: GitPushCredential?,
        pushOptions: GitPushOptions,
        continuation: AsyncStream<GitSyncEvent>.Continuation
    ) async {
        guard let binary = resolveBinary() else {
            continuation.yield(
                .line(
                    GitStreamLine(
                        source: .stderr,
                        text: GitSyncError.gitNotFound.localizedDescription)))
            continuation.yield(.finished(exitCode: 127))
            return
        }

        let injectionArgs = credential.map { GitCredentialInjection.arguments(login: $0.login) } ?? []
        let environment = credential.map { GitCredentialInjection.environment(token: $0.token) }

        // The chosen remote reaches git as a positional arg, so it gets the same
        // leading-"-" option-injection guard as branch names. An unsafe value is
        // dropped rather than injected — git then falls back to the default remote.
        let remotePositional =
            GitBranchName.isSafe(pushOptions.remote) ? [pushOptions.remote] : []

        let firstAttempt =
            injectionArgs
            + (operation == .push
                ? ["-C", repoURL.path, "push"] + pushOptions.pushFlags + remotePositional
                : ["-C", repoURL.path, "pull"])

        let result = await runOnce(
            binary: binary, args: firstAttempt, environment: environment, continuation: continuation)

        if result.authPromptHit {
            // Don't try to retry; the user must configure credentials externally.
            continuation.yield(.finished(exitCode: result.exitCode))
            return
        }

        if emitCredentialRejectedIfNeeded(result, credential: credential, continuation: continuation) {
            continuation.yield(.finished(exitCode: result.exitCode))
            return
        }

        // isSafe: branch and remote reach git as positional args — the option-injection
        // guard the other runners use. Flags + chosen remote carry over so the
        // --set-upstream retry mirrors the first attempt.
        if operation == .push,
            result.exitCode != 0,
            let branch = currentBranch,
            GitBranchName.isSafe(branch),
            GitBranchName.isSafe(pushOptions.remote),
            NoUpstreamDetector.looksLikeMissingUpstream(result.stderrLines)
        {
            continuation.yield(.retryingWithUpstream(branch: branch))
            let retryArgs =
                injectionArgs + ["-C", repoURL.path, "push"] + pushOptions.pushFlags
                + ["--set-upstream", pushOptions.remote, branch]
            let retry = await runOnce(
                binary: binary, args: retryArgs, environment: environment, continuation: continuation)
            _ = emitCredentialRejectedIfNeeded(retry, credential: credential, continuation: continuation)
            continuation.yield(.finished(exitCode: retry.exitCode))
            return
        }

        continuation.yield(.finished(exitCode: result.exitCode))
    }

    private func emitCredentialRejectedIfNeeded(
        _ outcome: RunOutcome,
        credential: GitPushCredential?,
        continuation: AsyncStream<GitSyncEvent>.Continuation
    ) -> Bool {
        guard let credential, outcome.exitCode != 0,
            PushAuthFailureDetector.looksLikeAuthFailure(outcome.stderrLines)
        else { return false }
        continuation.yield(.credentialRejected(login: credential.login))
        return true
    }

    private struct RunOutcome {
        let exitCode: Int32
        let stderrLines: [String]
        let authPromptHit: Bool
    }

    private func runOnce(
        binary: URL,
        args: [String],
        environment: [String: String]?,
        continuation: AsyncStream<GitSyncEvent>.Continuation
    ) async -> RunOutcome {
        let stream: AsyncStream<GitStreamLine>
        let outcome: () async -> GitStreamOutcome
        do {
            (stream, outcome) = try await streamer.stream(
                binaryURL: binary, args: args, cwd: nil, environment: environment)
        } catch let error as GitProcessRunnerError {
            continuation.yield(
                .line(
                    GitStreamLine(
                        source: .stderr, text: error.localizedDescription)))
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
                // Deliberately no task.cancel(): stdin = nullDevice means git exits
                // on its own within ms of the prompt, and cancelling would race that
                // exit and risk killing an unrelated recycled PID.
            }
            continuation.yield(.line(line))
            if Task.isCancelled { break }
        }
        let exit = await outcome()
        return RunOutcome(
            exitCode: exit.exitCode, stderrLines: stderrLines, authPromptHit: authHit)
    }
}
