import Foundation
import os

nonisolated enum GitBranchState: Sendable, Equatable, Hashable {
    case branch(String)
    case detached(sha: String)
}

nonisolated enum GitCurrentBranchError: Error, Sendable, Equatable {
    case gitNotFound
    case notAGitRepo
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .notAGitRepo:
            return "Not a git repository."
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitCurrentBranchRunning: Sendable {
    func run(repoURL: URL) async throws -> GitBranchState
}

nonisolated struct GitCurrentBranchRunner: GitCurrentBranchRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func run(repoURL: URL) async throws -> GitBranchState {
        guard let binary = resolveBinary() else { throw GitCurrentBranchError.gitNotFound }

        // `git symbolic-ref --short HEAD` returns the branch name on success.
        // Exit-code 128 means detached HEAD (HEAD points at a SHA, not a ref).
        // Any other non-zero exit is propagated as nonZeroExit so the caller
        // can surface it instead of guessing.
        let symbolic: GitSpawnResult
        do {
            symbolic = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "symbolic-ref", "--short", "HEAD"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }

        if symbolic.exitCode == 0 {
            let name = String(decoding: symbolic.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .branch(name)
        }

        // Exit non-zero — could be detached HEAD or not-a-repo. Use rev-parse
        // to differentiate: it exits 128 if the dir isn't a repo at all.
        let revParse: GitSpawnResult
        do {
            revParse = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "rev-parse", "--short", "HEAD"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }

        if revParse.exitCode == 0 {
            let sha = String(decoding: revParse.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .detached(sha: sha)
        }

        let stderr = String(decoding: revParse.stderr, as: UTF8.self)
        if stderr.contains("not a git repository") || stderr.contains("Not a git repository") {
            throw GitCurrentBranchError.notAGitRepo
        }
        throw GitCurrentBranchError.nonZeroExit(code: revParse.exitCode, stderr: stderr)
    }

    static func map(_ error: GitProcessRunnerError) -> GitCurrentBranchError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}

nonisolated final class MockGitCurrentBranchRunner: GitCurrentBranchRunning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State: Sendable {
        var outputs: [URL: GitBranchState] = [:]
        var error: GitCurrentBranchError?
        var calls: [URL] = []
    }

    var outputs: [URL: GitBranchState] {
        get { lock.withLock { $0.outputs } }
        set { lock.withLock { $0.outputs = newValue } }
    }

    var error: GitCurrentBranchError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    var calls: [URL] {
        lock.withLock { $0.calls }
    }

    func run(repoURL: URL) async throws -> GitBranchState {
        let result: (error: GitCurrentBranchError?, output: GitBranchState?) =
            lock.withLock { state in
                state.calls.append(repoURL)
                return (state.error, state.outputs[repoURL])
            }
        if let error = result.error { throw error }
        return result.output ?? .branch("main")
    }
}
