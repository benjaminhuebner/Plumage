import Foundation

nonisolated enum GitWorkingDiffError: Error, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(_, let stderr):
            return "git diff failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitWorkingDiffRunning: Sendable {
    func diffWorking(repoURL: URL, path: String) async throws -> String
    func diffStaged(repoURL: URL, path: String) async throws -> String
}

nonisolated struct GitWorkingDiffRunner: GitWorkingDiffRunning {
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
        guard let binary = resolveBinary() else { throw GitWorkingDiffError.gitNotFound }
        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path] + args,
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        if result.exitCode != 0 {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw GitWorkingDiffError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    static func map(_ error: GitProcessRunnerError) -> GitWorkingDiffError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}
