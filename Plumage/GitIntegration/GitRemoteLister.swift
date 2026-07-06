import Foundation

nonisolated struct GitRemoteLister: Sendable, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func remotes(repoURL: URL) async throws -> [String] {
        let result = try await invokeGit(
            repoURL: repoURL,
            args: ["remote"],
            command: "git remote")
        return Self.parse(output: String(decoding: result.stdout, as: UTF8.self))
    }

    static func parse(output: String) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
