import Foundation

nonisolated enum GitCommitError: Error, Sendable, Equatable {
    case emptyMessage
    case nothingToCommit

    var displayMessage: String {
        switch self {
        case .emptyMessage:
            return "Commit message is empty."
        case .nothingToCommit:
            return "Nothing staged — commit aborted."
        }
    }
}

nonisolated protocol GitCommitting: Sendable {
    func commit(repoURL: URL, message: String) async throws
}

nonisolated struct GitCommitRunner: GitCommitting, GitCommandRunning {
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

        // Spec called for `--file=-` via stdin to avoid quoting bugs. The
        // current GitProcessRunning impl sets `standardInput = nullDevice`
        // and Process.arguments is already passed verbatim (no shell, no
        // quoting), so `-m <message>` is safe — newlines, quotes, $ all go
        // through untouched. Switching to stdin would require widening the
        // process protocol for no behavioural gain.
        let result = try await spawnGit(
            repoURL: repoURL,
            args: ["commit", "-m", message],
            command: "git commit"
        )
        if result.exitCode == 0 { return }

        let stderr = String(decoding: result.stderr, as: UTF8.self)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        let combined = stderr + stdout
        // `git commit` exits 1 with "nothing to commit" when nothing is
        // staged; surface that as a typed error so the UI shows a friendly
        // message instead of dumping git's stderr verbatim.
        if combined.localizedCaseInsensitiveContains("nothing to commit")
            || combined.localizedCaseInsensitiveContains("no changes added to commit")
        {
            throw GitCommitError.nothingToCommit
        }
        throw GitCommandError.nonZeroExit(
            command: "git commit", code: result.exitCode, stderr: stderr)
    }
}
