import Foundation

nonisolated enum GitTagListError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case listFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .listFailed(let stderr):
            return "git for-each-ref failed: \(stderr.prefix(200))"
        }
    }
}

nonisolated struct GitTagLister: Sendable {
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
        guard let binary = resolveBinary() else {
            throw GitTagListError.gitNotFound
        }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["for-each-ref", "--sort=-creatordate", "--format=%(refname:short)", "refs/tags/"],
            cwd: repoURL
        )
        guard result.exitCode == 0 else {
            throw GitTagListError.listFailed(
                stderr: String(decoding: result.stderr, as: UTF8.self))
        }
        return Self.parse(output: String(decoding: result.stdout, as: UTF8.self))
    }

    static func parse(output: String) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
