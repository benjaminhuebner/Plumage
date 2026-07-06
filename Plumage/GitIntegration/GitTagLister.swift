import Foundation

nonisolated struct GitTagLister: Sendable, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func tags(repoURL: URL) async throws -> [String] {
        let result = try await invokeGit(
            repoURL: repoURL,
            args: ["for-each-ref", "--sort=-creatordate", "--format=%(refname:short)", "refs/tags/"],
            command: "git for-each-ref")
        return Self.parse(output: String(decoding: result.stdout, as: UTF8.self))
    }

    static func parse(output: String) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
