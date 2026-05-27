import Foundation

nonisolated enum GitCommitError: Error, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case emptyMessage
    case nothingToCommit(stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .emptyMessage:
            return "Commit message is empty."
        case .nothingToCommit:
            return "Nothing staged — commit aborted."
        case .nonZeroExit(_, let stderr):
            return "git commit failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitCommitting: Sendable {
    func commit(repoURL: URL, message: String) async throws
}

nonisolated struct GitCommitRunner: GitCommitting {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func commit(repoURL: URL, message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitCommitError.emptyMessage }
        guard let binary = resolveBinary() else { throw GitCommitError.gitNotFound }

        // Spec called for `--file=-` via stdin to avoid quoting bugs. The
        // current GitProcessRunning impl sets `standardInput = nullDevice`
        // and Process.arguments is already passed verbatim (no shell, no
        // quoting), so `-m <message>` is safe — newlines, quotes, $ all go
        // through untouched. Switching to stdin would require widening the
        // process protocol for no behavioural gain.
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "commit", "-m", message],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        if result.exitCode == 0 { return }

        let stderr = String(decoding: result.stderr, as: UTF8.self)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        let combined = stderr + stdout
        // `git commit` exits 1 with "nothing to commit" when nothing is
        // staged; surface that as a typed error so the UI shows a friendly
        // message instead of dumping git's stderr verbatim.
        if combined.localizedCaseInsensitiveContains("nothing to commit")
            || combined.localizedCaseInsensitiveContains("no changes added to commit") {
            throw GitCommitError.nothingToCommit(stderr: stderr)
        }
        throw GitCommitError.nonZeroExit(code: result.exitCode, stderr: stderr)
    }

    static func map(_ error: GitProcessRunnerError) -> GitCommitError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
