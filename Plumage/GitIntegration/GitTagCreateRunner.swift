import Foundation

nonisolated enum GitTagCreateError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case invalidName(String)
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .invalidName(let name):
            return "Invalid tag name: '\(name)'"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git tag failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitTagCreating: Sendable {
    func createTag(name: String, message: String?, repoURL: URL) async throws
}

nonisolated struct GitTagCreateRunner: GitTagCreating {
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
        var args = ["-C", repoURL.path, "tag"]
        if trimmedMessage.isEmpty {
            args += [name]
        } else {
            args += ["-a", name, "-m", trimmedMessage]
        }
        guard let binary = resolveBinary() else { throw GitTagCreateError.gitNotFound }
        let result: GitSpawnResult
        do {
            result = try await runner.run(binaryURL: binary, args: args, cwd: nil)
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        guard result.exitCode == 0 else {
            throw GitTagCreateError.nonZeroExit(
                code: result.exitCode, stderr: String(decoding: result.stderr, as: UTF8.self))
        }
    }

    static func map(_ error: GitProcessRunnerError) -> GitTagCreateError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
