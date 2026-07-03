import Foundation

nonisolated protocol GitWorkingDiffRunning: Sendable {
    func diffWorking(repoURL: URL, path: String) async throws -> String
    func diffStaged(repoURL: URL, path: String) async throws -> String
}

nonisolated struct GitWorkingDiffRunner: GitWorkingDiffRunning, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func diffWorking(repoURL: URL, path: String) async throws -> String {
        try await diff(repoURL: repoURL, args: ["diff", "--", path])
    }

    func diffStaged(repoURL: URL, path: String) async throws -> String {
        try await diff(repoURL: repoURL, args: ["diff", "--cached", "--", path])
    }

    private func diff(repoURL: URL, args: [String]) async throws -> String {
        let result = try await invokeGit(repoURL: repoURL, args: args, command: "git diff")
        return String(decoding: result.stdout, as: UTF8.self)
    }
}
