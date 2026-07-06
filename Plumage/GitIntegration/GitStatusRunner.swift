import Foundation

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

    // Single-letter badge for UI rendering — picks staged status first, falls
    // back to unstaged, treats untracked as "?". Mirrors what git prints in
    // `git status --short` for the same row.
    var badge: Character {
        if isUntracked { return "?" }
        if stagedStatus != " " { return stagedStatus }
        return unstagedStatus
    }
}

nonisolated enum GitStatusError: LocalizedError, Sendable, Equatable {
    case malformedOutput(String)

    var errorDescription: String? {
        switch self {
        case .malformedOutput(let detail):
            return "git status output malformed: \(detail)"
        }
    }
}

nonisolated protocol GitStatusRunning: Sendable {
    func run(repoURL: URL) async throws -> [GitFileStatus]
}

nonisolated struct GitStatusRunner: GitStatusRunning, GitCommandRunning {
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
        let result = try await invokeGit(
            repoURL: repoURL,
            args: ["status", "--porcelain=v1", "-z"],
            command: "git status"
        )
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
            let needsOriginal =
                staged == "R" || staged == "C"
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
}
