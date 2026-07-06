import Foundation

nonisolated enum GitTagCreateError: LocalizedError, Sendable, Equatable {
    case invalidName(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid tag name: '\(name)'"
        }
    }
}

nonisolated protocol GitTagCreating: Sendable {
    func createTag(name: String, message: String?, repoURL: URL) async throws
}

nonisolated struct GitTagCreateRunner: GitTagCreating, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func createTag(name: String, message: String?, repoURL: URL) async throws {
        guard GitBranchName.isSafe(name) else { throw GitTagCreateError.invalidName(name) }
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var args = ["tag"]
        if trimmedMessage.isEmpty {
            args += [name]
        } else {
            args += ["-a", name, "-m", trimmedMessage]
        }
        try await invokeGit(repoURL: repoURL, args: args, command: "git tag")
    }
}
