import Foundation

nonisolated struct WorktreeProvisionResult: Equatable, Sendable {
    let worktreeRoot: URL
    let reusedExisting: Bool
}

nonisolated enum WorktreeProvisionError: LocalizedError, Sendable, Equatable {
    case unsafeSlug(String)
    case scriptMissing(path: String)
    case pathOccupied(path: String)
    case scriptFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .unsafeSlug(let slug):
            return "Issue slug \"\(slug)\" is not safe to pass to the worktree setup script."
        case .scriptMissing(let path):
            return "Bundled setup-worktree.sh is missing at \(path) — the app bundle looks damaged."
        case .pathOccupied(let path):
            return "\(path) already exists and is not a worktree of this repository — move it aside first."
        case .scriptFailed(let message):
            return message.isEmpty ? "setup-worktree.sh failed without a message." : message
        }
    }
}

nonisolated struct WorktreeProvisioner: Sendable {
    let runner: any GitProcessRunning
    let lister: GitWorktreeLister
    let scriptURL: URL

    init(
        runner: any GitProcessRunning = ProductionGitProcessRunner(),
        lister: GitWorktreeLister = GitWorktreeLister(),
        scriptURL: URL = Self.bundledSetupScript
    ) {
        self.runner = runner
        self.lister = lister
        self.scriptURL = scriptURL
    }

    static var bundledSetupScript: URL {
        NewProjectAssets.bundledRoot
            .appending(path: "skills/plumage-implement/scripts/setup-worktree.sh")
    }

    static func expectedWorktreeRoot(projectRoot: URL, slug: String) -> URL {
        projectRoot.deletingLastPathComponent()
            .appending(
                component: "\(projectRoot.lastPathComponent)-\(slug)",
                directoryHint: .isDirectory
            )
    }

    func provision(slug: String, projectRoot: URL) async throws -> WorktreeProvisionResult {
        // A crafted slug like "--init-file=…" would be parsed as a script option.
        guard GitBranchName.isSafe(slug) else {
            throw WorktreeProvisionError.unsafeSlug(slug)
        }
        let target = Self.expectedWorktreeRoot(projectRoot: projectRoot, slug: slug)

        // The script refuses an existing target; a worktree of this repo at
        // the expected path is reused instead (a resumed run takes over).
        if FileManager.default.fileExists(atPath: target.path) {
            let worktrees = try await lister.worktrees(repoURL: projectRoot)
            if worktrees.contains(where: { Self.sameLocation($0.path, target) }) {
                return WorktreeProvisionResult(worktreeRoot: target, reusedExisting: true)
            }
            throw WorktreeProvisionError.pathOccupied(path: target.path)
        }

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw WorktreeProvisionError.scriptMissing(path: scriptURL.path)
        }

        // Via /bin/bash so the resource's executable bit is irrelevant.
        let result = try await runner.run(
            binaryURL: URL(filePath: "/bin/bash"),
            args: [scriptURL.path, slug],
            cwd: projectRoot
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorktreeProvisionError.scriptFailed(message: String(stderr.suffix(300)))
        }
        return WorktreeProvisionResult(worktreeRoot: target, reusedExisting: false)
    }

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
