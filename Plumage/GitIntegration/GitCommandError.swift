import Foundation

// One error shape for the simple one-shot git runners. `command` labels
// nonZeroExit so every runner keeps its historical display text
// ("git status failed: …", "git failed: …") character-identical.
nonisolated enum GitCommandError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(command: String, code: Int32, stderr: String)

    init(command: String, mapping error: GitProcessRunnerError) {
        switch error {
        case .gitNotFound:
            self = .gitNotFound
        case .spawnFailed(let description):
            self = .spawnFailed(description)
        case .nonZeroExit(let code, let stderr):
            self = .nonZeroExit(command: command, code: code, stderr: stderr)
        }
    }

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(let command, _, let stderr):
            return "\(command) failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

nonisolated protocol GitCommandRunning: Sendable {
    var runner: any GitProcessRunning { get }
    var resolveBinary: @Sendable () -> URL? { get }
}

extension GitCommandRunning {
    // Spawns `git -C <repo> <args>` and maps missing-binary/spawn failures;
    // exit-code interpretation stays with the caller.
    func spawnGit(repoURL: URL, args: [String], command: String) async throws -> GitSpawnResult {
        guard let binary = resolveBinary() else { throw GitCommandError.gitNotFound }
        do {
            return try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path] + args,
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw GitCommandError(command: command, mapping: error)
        }
    }

    // spawnGit plus the standard non-zero-exit mapping.
    @discardableResult
    func invokeGit(repoURL: URL, args: [String], command: String) async throws -> GitSpawnResult {
        let result = try await spawnGit(repoURL: repoURL, args: args, command: command)
        guard result.exitCode == 0 else {
            throw GitCommandError.nonZeroExit(
                command: command,
                code: result.exitCode,
                stderr: String(decoding: result.stderr, as: UTF8.self)
            )
        }
        return result
    }
}
