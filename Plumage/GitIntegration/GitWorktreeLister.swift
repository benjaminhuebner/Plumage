import Foundation

nonisolated struct GitWorktree: Equatable, Sendable {
    let path: URL
    let branch: String?
}

nonisolated enum GitWorktreeListError: LocalizedError, Sendable, Equatable {
    case gitNotFound
    case listFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .listFailed(let stderr):
            return "git worktree list failed: \(stderr.prefix(200))"
        }
    }
}

nonisolated struct GitWorktreeLister: Sendable {
    let runner: any GitProcessRunning
    let resolveBinary: @Sendable () -> URL?

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        resolveBinary: @escaping @Sendable () -> URL? = { ToolchainLocator.git() }
    ) {
        self.runner = runner
        self.resolveBinary = resolveBinary
    }

    func worktrees(repoURL: URL) async throws -> [GitWorktree] {
        guard let binary = resolveBinary() else {
            throw GitWorktreeListError.gitNotFound
        }
        let result = try await runner.run(
            binaryURL: binary,
            args: ["worktree", "list", "--porcelain"],
            cwd: repoURL
        )
        guard result.exitCode == 0 else {
            throw GitWorktreeListError.listFailed(
                stderr: String(decoding: result.stderr, as: UTF8.self))
        }
        return Self.parse(porcelain: String(decoding: result.stdout, as: UTF8.self))
    }

    // Porcelain output is blocks separated by blank lines; each block starts
    // with `worktree <path>` followed by attribute lines (`HEAD <sha>`,
    // `branch refs/heads/<name>`, `detached`, `bare`, `locked`, `prunable`).
    static func parse(porcelain: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        var path: String?
        var branch: String?

        func flush() {
            if let path {
                result.append(
                    GitWorktree(
                        path: URL(filePath: path, directoryHint: .isDirectory),
                        branch: branch
                    ))
            }
            path = nil
            branch = nil
        }

        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                let headsPrefix = "refs/heads/"
                branch = ref.hasPrefix(headsPrefix) ? String(ref.dropFirst(headsPrefix.count)) : ref
            }
        }
        flush()
        return result
    }
}
