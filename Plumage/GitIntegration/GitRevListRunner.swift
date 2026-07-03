import Foundation

nonisolated enum GitRevListError: Error, Sendable, Equatable {
    case unsafeReference(String)
    case unparsableCount(String)
}

nonisolated struct GitRevListRunner: Sendable, GitCommandRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func countCommits(repoURL: URL, from sha: String, to branch: String) async throws -> Int {
        guard isHexSHA(sha) else {
            throw GitRevListError.unsafeReference(sha)
        }
        guard GitBranchName.isSafe(branch) else {
            throw GitRevListError.unsafeReference(branch)
        }
        let result = try await invokeGit(
            repoURL: repoURL,
            args: ["rev-list", "--count", "\(sha)..\(branch)"],
            command: "git rev-list"
        )
        let output = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(output) else {
            throw GitRevListError.unparsableCount(output)
        }
        return count
    }

    private func isHexSHA(_ sha: String) -> Bool {
        sha.count >= 7 && sha.count <= 64 && sha.allSatisfy(\.isHexDigit)
    }
}
