import Foundation

nonisolated enum GitInitError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git init failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitInitializing: Sendable {
    func initRepo(at url: URL, defaultBranch: String) async throws
}

nonisolated struct GitInitRunner: GitInitializing {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func initRepo(at url: URL, defaultBranch: String = "main") async throws {
        guard GitBranchName.isSafe(defaultBranch) else {
            throw GitInitError.nonZeroExit(
                code: 128, stderr: "invalid branch name: '\(defaultBranch)'")
        }
        guard let binary = resolveBinary() else { throw GitInitError.gitNotFound }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary, args: ["init", "-b", defaultBranch], cwd: url)
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        guard result.exitCode == 0 else {
            throw GitInitError.nonZeroExit(
                code: result.exitCode, stderr: String(decoding: result.stderr, as: UTF8.self))
        }
    }

    static func map(_ error: GitProcessRunnerError) -> GitInitError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
