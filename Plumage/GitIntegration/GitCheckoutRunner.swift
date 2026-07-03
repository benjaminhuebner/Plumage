import Foundation

nonisolated enum GitCheckoutError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case unsafeBranchName(name: String)
    case checkoutFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .unsafeBranchName(let name):
            return "Branch name \"\(name.prefix(80))\" is not a valid git branch name."
        case .checkoutFailed(let stderr):
            return "git checkout failed: \(stderr.prefix(300))"
        }
    }
}

nonisolated struct GitCheckoutRunner: Sendable {
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
        guard let binary = resolveBinary() else {
            throw GitCheckoutError.gitNotFound
        }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["-C", repoURL.path, "checkout"] + extraArgs + [branch],
            cwd: nil
        )
        guard result.exitCode == 0 else {
            throw GitCheckoutError.checkoutFailed(
                stderr: String(decoding: result.stderr, as: UTF8.self))
        }
    }
}
