import Foundation

nonisolated enum GitStageError: Error, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case emptyPathList

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .emptyPathList:
            return "No paths supplied — refusing to stage/unstage nothing."
        }
    }
}

nonisolated protocol GitStaging: Sendable {
    func stage(repoURL: URL, paths: [String]) async throws
    func unstage(repoURL: URL, paths: [String]) async throws
}

nonisolated struct GitStageRunner: GitStaging {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func stage(repoURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { throw GitStageError.emptyPathList }
        try await invoke(repoURL: repoURL, args: ["add", "--"] + paths)
    }

    func unstage(repoURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { throw GitStageError.emptyPathList }
        // `git reset HEAD --` is the canonical unstage for both pre-/post-
        // initial-commit repos. `git restore --staged` would be cleaner but
        // is gated on a clean working-tree assumption that doesn't hold for
        // newly-deleted files; the older `reset HEAD` covers every case.
        try await invoke(repoURL: repoURL, args: ["reset", "HEAD", "--"] + paths)
    }

    private func invoke(repoURL: URL, args: [String]) async throws {
        guard let binary = resolveBinary() else { throw GitStageError.gitNotFound }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path] + args,
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        if result.exitCode != 0 {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw GitStageError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
    }

    static func map(_ error: GitProcessRunnerError) -> GitStageError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
