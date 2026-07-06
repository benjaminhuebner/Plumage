import Foundation

nonisolated enum GitCheckoutError: LocalizedError, Sendable, Equatable {
    case unsafeBranchName(name: String)

    var errorDescription: String? {
        switch self {
        case .unsafeBranchName(let name):
            return "Branch name \"\(name.prefix(80))\" is not a valid git branch name."
        }
    }
}

nonisolated struct GitCheckoutRunner: Sendable, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func checkout(repoURL: URL, branch: String) async throws {
        try await run(repoURL: repoURL, branch: branch, extraArgs: [])
    }

    func createBranch(repoURL: URL, name: String) async throws {
        try await run(repoURL: repoURL, branch: name, extraArgs: ["-b"])
    }

    private func run(repoURL: URL, branch: String, extraArgs: [String]) async throws {
        guard GitBranchName.isSafe(branch) else {
            throw GitCheckoutError.unsafeBranchName(name: branch)
        }
        try await invokeGit(
            repoURL: repoURL,
            args: ["checkout"] + extraArgs + [branch],
            command: "git checkout")
    }
}
