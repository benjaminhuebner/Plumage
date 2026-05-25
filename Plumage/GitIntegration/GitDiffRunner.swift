import Foundation

nonisolated enum GitDiffError: Error, Sendable, Equatable {
    case gitNotFound
    case repoNotFound(URL)
    case baseBranchMissing(String)
    case nonZeroExit(code: Int32, stderr: String)
    case spawnFailed(String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` nicht gefunden — Command-Line-Tools installiert?"
        case .repoNotFound(let url):
            return "Kein Git-Repo gefunden in `\(url.path)`."
        case .baseBranchMissing(let base):
            return "Base-Branch `\(base)` nicht gefunden — Repo initial?"
        case .nonZeroExit(_, let stderr):
            return "git diff fehlgeschlagen: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        }
    }
}

nonisolated struct GitDiffRunner: Sendable {
    let runner: GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: GitProcessRunning,
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func run(repoURL: URL, base: String = "main") async throws -> String {
        guard let binary = resolveBinary() else {
            throw GitDiffError.gitNotFound
        }
        try await verifyRepoExists(binary: binary, repoURL: repoURL)
        try await verifyBaseBranch(binary: binary, repoURL: repoURL, base: base)
        return try await runDiff(binary: binary, repoURL: repoURL, base: base)
    }

    private func verifyRepoExists(binary: URL, repoURL: URL) async throws {
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "rev-parse", "--git-dir"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw mapRunnerError(error)
        }
        if result.exitCode != 0 {
            throw GitDiffError.repoNotFound(repoURL)
        }
    }

    private func verifyBaseBranch(binary: URL, repoURL: URL, base: String) async throws {
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "rev-parse", "--verify", "--quiet", base],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw mapRunnerError(error)
        }
        if result.exitCode != 0 {
            throw GitDiffError.baseBranchMissing(base)
        }
    }

    private func runDiff(binary: URL, repoURL: URL, base: String) async throws -> String {
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "diff", "\(base)...HEAD"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw mapRunnerError(error)
        }
        if result.exitCode != 0 {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw GitDiffError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    private func mapRunnerError(_ error: GitProcessRunnerError) -> GitDiffError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
