import Foundation

nonisolated enum GitRevListError: Error, Sendable, Equatable {
    case gitNotFound
    case unsafeReference(String)
    case nonZeroExit(code: Int32, stderr: String)
    case spawnFailed(String)
    case unparsableCount(String)
}

nonisolated struct GitRevListRunner: Sendable {
    let runner: GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: GitProcessRunning = ProductionGitProcessRunner(),
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
        guard let binary = resolveBinary() else {
            throw GitRevListError.gitNotFound
        }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "rev-list", "--count", "\(sha)..\(branch)"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw map(error)
        }
        if result.exitCode != 0 {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw GitRevListError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
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

    private func map(_ error: GitProcessRunnerError) -> GitRevListError {
        switch error {
        case .gitNotFound: .gitNotFound
        case .spawnFailed(let description): .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
