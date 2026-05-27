import Foundation
import os

// Per-file status from `git status --porcelain=v1 -z`. Two single-character
// codes: stagedStatus reflects the index (HEAD → index), unstagedStatus the
// working tree (index → working tree). `?` in both slots means untracked.
nonisolated struct GitFileStatus: Sendable, Equatable, Hashable, Identifiable {
    let path: String
    let stagedStatus: Character
    let unstagedStatus: Character
    // For renames/copies the porcelain block carries TWO paths: new\0old.
    // `originalPath` holds the source side when present.
    let originalPath: String?

    var id: String { path }

    var isUntracked: Bool { stagedStatus == "?" && unstagedStatus == "?" }
    var isStaged: Bool { !isUntracked && stagedStatus != " " }
    var isUnstaged: Bool { !isUntracked && unstagedStatus != " " }

    // Single-letter badge for UI rendering — picks staged status first, falls
    // back to unstaged, treats untracked as "?". Mirrors what git prints in
    // `git status --short` for the same row.
    var badge: Character {
        if isUntracked { return "?" }
        if stagedStatus != " " { return stagedStatus }
        return unstagedStatus
    }
}

nonisolated enum GitStatusError: Error, Sendable, Equatable {
    case gitNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case spawnFailed(String)
    case malformedOutput(String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .nonZeroExit(_, let stderr):
            return "git status failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .malformedOutput(let detail):
            return "git status output malformed: \(detail)"
        }
    }
}

nonisolated protocol GitStatusRunning: Sendable {
    func run(repoURL: URL) async throws -> [GitFileStatus]
}

nonisolated struct GitStatusRunner: GitStatusRunning {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func run(repoURL: URL) async throws -> [GitFileStatus] {
        guard let binary = resolveBinary() else { throw GitStatusError.gitNotFound }

        let result: GitSpawnResult
        do {
            result = try await runner.run(
                binaryURL: binary,
                args: ["-C", repoURL.path, "status", "--porcelain=v1", "-z"],
                cwd: nil
            )
        } catch let error as GitProcessRunnerError {
            throw Self.map(error)
        }
        if result.exitCode != 0 {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw GitStatusError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return try Self.parse(result.stdout)
    }

    // Porcelain v1 with -z: each entry is `XY <path>\0` where X is stagedStatus
    // and Y is unstagedStatus. Renames/copies carry the new path first then
    // `\0<oldPath>\0` — i.e. one extra NUL-terminated field after the row.
    static func parse(_ data: Data) throws -> [GitFileStatus] {
        guard !data.isEmpty else { return [] }
        // Split into NUL-terminated tokens. `componentsSeparated` keeps a
        // trailing empty string after the last NUL — drop it.
        let bytes = [UInt8](data)
        var tokens: [String] = []
        var current = Data()
        for byte in bytes {
            if byte == 0 {
                tokens.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        // Tolerate a non-NUL-terminated tail just in case some git binary
        // emits one — we'd rather parse a near-miss than throw.
        if !current.isEmpty {
            tokens.append(String(decoding: current, as: UTF8.self))
        }

        var results: [GitFileStatus] = []
        var idx = 0
        while idx < tokens.count {
            let token = tokens[idx]
            idx += 1
            // Each row starts with `XY ` (status block + space) followed by
            // the path. A length < 3 is structural noise; bail with a typed
            // error so the caller can surface "git status output malformed"
            // rather than silently dropping data.
            if token.isEmpty { continue }
            guard token.count >= 3 else {
                throw GitStatusError.malformedOutput("row shorter than `XY <path>`: \(token)")
            }
            let chars = Array(token)
            let staged = chars[0]
            let unstaged = chars[1]
            // chars[2] is ' '
            let path = String(chars.dropFirst(3))

            // Renames/copies push one extra token with the original path.
            // Both staged and unstaged sides can carry R/C — the second slot
            // happens on staged renames followed by an unstaged edit.
            let needsOriginal = staged == "R" || staged == "C"
                || unstaged == "R" || unstaged == "C"
            var originalPath: String?
            if needsOriginal {
                guard idx < tokens.count else {
                    throw GitStatusError.malformedOutput(
                        "rename row missing original-path token: \(token)")
                }
                originalPath = tokens[idx]
                idx += 1
            }

            results.append(
                GitFileStatus(
                    path: path,
                    stagedStatus: staged,
                    unstagedStatus: unstaged,
                    originalPath: originalPath
                )
            )
        }
        return results
    }

    static func map(_ error: GitProcessRunnerError) -> GitStatusError {
        switch error {
        case .gitNotFound: return .gitNotFound
        case .spawnFailed(let description): return .spawnFailed(description)
        case .nonZeroExit(let code, let stderr): return .nonZeroExit(code: code, stderr: stderr)
        }
    }
}

// Test-only stub for higher-level features (GitCommitModel, ProjectStatusBar).
nonisolated final class MockGitStatusRunner: GitStatusRunning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State: Sendable {
        var outputs: [URL: [GitFileStatus]] = [:]
        var error: GitStatusError?
        var calls: [URL] = []
    }

    var outputs: [URL: [GitFileStatus]] {
        get { lock.withLock { $0.outputs } }
        set { lock.withLock { $0.outputs = newValue } }
    }

    var error: GitStatusError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    var calls: [URL] {
        get { lock.withLock { $0.calls } }
    }

    func run(repoURL: URL) async throws -> [GitFileStatus] {
        let result: (error: GitStatusError?, output: [GitFileStatus]) = lock.withLock { state in
            state.calls.append(repoURL)
            return (state.error, state.outputs[repoURL] ?? [])
        }
        if let error = result.error { throw error }
        return result.output
    }
}
