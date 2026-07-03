import Foundation

nonisolated enum GitStageError: Error, Sendable, Equatable {
    case emptyPathList

    var displayMessage: String {
        switch self {
        case .emptyPathList:
            return "No paths supplied — refusing to stage/unstage nothing."
        }
    }
}

nonisolated protocol GitStaging: Sendable {
    func stage(repoURL: URL, paths: [String]) async throws
    func unstage(repoURL: URL, paths: [String]) async throws
}

nonisolated struct GitStageRunner: GitStaging, GitCommandRunning {
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
        try await invokeGit(repoURL: repoURL, args: ["add", "--"] + paths, command: "git")
    }

    func unstage(repoURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { throw GitStageError.emptyPathList }
        // `git reset HEAD --` is the canonical unstage for both pre-/post-
        // initial-commit repos. `git restore --staged` would be cleaner but
        // is gated on a clean working-tree assumption that doesn't hold for
        // newly-deleted files; the older `reset HEAD` covers every case.
        try await invokeGit(repoURL: repoURL, args: ["reset", "HEAD", "--"] + paths, command: "git")
    }
}
