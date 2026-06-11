import Foundation

@testable import Plumage

// Tmp-repo helper for the merge-end-to-end integration test. Builds:
//   <tmpDir>/
//     .git/                         (initialized via `git init`)
//     .claude/issues/00001-x/spec.md
//     content.txt                   (committed on main, then more on the
//                                    issue branch — so the merge actually
//                                    fast-forwards a real diff)
//
// Class + deinit so tmpDir is cleaned up automatically when the instance goes
// out of scope (mirrors TestEnvironment). All properties are `let`, so the
// final class is plain Sendable — no @unchecked needed.
nonisolated final class TmpGitRepo: Sendable {
    let tmpDir: URL
    let specURL: URL
    let mainBranch: String
    let issueBranch: String
    let folderName: String

    private init(
        tmpDir: URL, specURL: URL,
        mainBranch: String, issueBranch: String, folderName: String
    ) {
        self.tmpDir = tmpDir
        self.specURL = specURL
        self.mainBranch = mainBranch
        self.issueBranch = issueBranch
        self.folderName = folderName
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    static func make(
        defaultBranch: String = "main",
        folderName: String = "00001-x",
        issueBranch: String = "issue/00001-x"
    ) async throws -> TmpGitRepo {
        let fileManager = FileManager.default
        let tmpDir = fileManager.temporaryDirectory
            .appendingPathComponent("TmpGitRepo-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Anything that throws after createDirectory must clean up tmpDir,
        // otherwise a partial-construction failure leaves the directory on
        // disk (the deinit only fires when an instance returns).
        do {
            // git init -b <defaultBranch>. Bypasses any global init.defaultBranch
            // config so the test is deterministic.
            try await runGit(["init", "-b", defaultBranch], cwd: tmpDir)
            // user.name / user.email — required for `git commit` to work without
            // a global git identity. Test-only values.
            try await runGit(["config", "user.name", "Test"], cwd: tmpDir)
            try await runGit(["config", "user.email", "test@plumage.invalid"], cwd: tmpDir)
            // commit.gpgsign=false so the test doesn't fail on hosts that have
            // GPG signing on by default in their global git config.
            try await runGit(["config", "commit.gpgsign", "false"], cwd: tmpDir)

            // Initial commit on default branch.
            let contentURL = tmpDir.appendingPathComponent("content.txt")
            try "main\n".write(to: contentURL, atomically: true, encoding: .utf8)
            try await runGit(["add", "content.txt"], cwd: tmpDir)
            try await runGit(["commit", "-m", "initial"], cwd: tmpDir)

            // Create the issue folder with a spec.md before branching, so the
            // branch carries the issue file too. Not committed to git — mirrors
            // Plumage's real-project setup where .claude/ is gitignored.
            let issueFolder =
                tmpDir
                .appendingPathComponent(".claude/issues", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try fileManager.createDirectory(at: issueFolder, withIntermediateDirectories: true)
            let specURL = issueFolder.appendingPathComponent("spec.md")
            try Self.specContent(branch: issueBranch).write(
                to: specURL, atomically: true, encoding: .utf8)
            // gitignore .claude/ so `git status --porcelain` stays empty
            // (Plumage's mergeToMain pre-check requires a clean tree).
            // wt/ hosts test worktrees inside tmpDir so deinit cleans them up.
            let gitignore = tmpDir.appendingPathComponent(".gitignore")
            try ".claude/\nwt/\n".write(to: gitignore, atomically: true, encoding: .utf8)
            try await runGit(["add", ".gitignore"], cwd: tmpDir)
            try await runGit(["commit", "-m", "ignore claude folder"], cwd: tmpDir)

            // Branch off and add a second commit so the merge is meaningful.
            try await runGit(["checkout", "-b", issueBranch], cwd: tmpDir)
            try "branch\n".write(to: contentURL, atomically: true, encoding: .utf8)
            try await runGit(["add", "content.txt"], cwd: tmpDir)
            try await runGit(["commit", "-m", "branch work"], cwd: tmpDir)

            return TmpGitRepo(
                tmpDir: tmpDir, specURL: specURL,
                mainBranch: defaultBranch,
                issueBranch: issueBranch,
                folderName: folderName
            )
        } catch {
            try? fileManager.removeItem(at: tmpDir)
            throw error
        }
    }

    // Leaves HEAD on the default branch so the issue branch stays free
    // for worktree checkouts.
    func divergeDefaultBranch() async throws {
        try await Self.runGit(["checkout", mainBranch], cwd: tmpDir)
        let url = tmpDir.appendingPathComponent("main-side.txt")
        try "main side\n".write(to: url, atomically: true, encoding: .utf8)
        try await Self.runGit(["add", "main-side.txt"], cwd: tmpDir)
        try await Self.runGit(["commit", "-m", "main side work"], cwd: tmpDir)
    }

    func addWorktree(checkingOut branch: String) async throws -> URL {
        let path = tmpDir.appendingPathComponent("wt", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try await Self.runGit(["worktree", "add", path.path, branch], cwd: tmpDir)
        return path
    }

    func fileContents(branch: String, path: String) async throws -> String {
        try await Self.runGit(["show", "\(branch):\(path)"], cwd: tmpDir)
    }

    func commitAll(message: String) async throws {
        try await Self.runGit(["add", "-A"], cwd: tmpDir)
        try await Self.runGit(["commit", "-m", message], cwd: tmpDir)
    }

    func currentBranch() async throws -> String {
        let output = try await Self.runGit(["symbolic-ref", "--short", "HEAD"], cwd: tmpDir)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func headSha(branch: String) async throws -> String {
        let output = try await Self.runGit(["rev-parse", branch], cwd: tmpDir)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitSubject(branch: String) async throws -> String {
        let output = try await Self.runGit(["log", "-1", "--format=%s", branch], cwd: tmpDir)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitCount(branch: String) async throws -> Int {
        let output = try await Self.runGit(["rev-list", "--count", branch], cwd: tmpDir)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func branchExists(_ branch: String) async -> Bool {
        do {
            let result = try await Self.runGitAllowingFailure(
                ["rev-parse", "--verify", branch], cwd: tmpDir)
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    static func specContent(branch: String) -> String {
        """
        ---
        id: 1
        title: Sample
        type: feature
        status: waiting-for-review
        created: 2026-05-25T19:00:00Z
        updated: 2026-05-25T19:00:00Z
        branch: \(branch)
        labels: []
        model: null
        ---

        Body content.
        """
    }

    // MARK: - Git shell-out

    struct GitInvocationFailure: Error, CustomStringConvertible {
        let args: [String]
        let exitCode: Int32
        let stderr: String
        var description: String {
            "git \(args.joined(separator: " ")) failed (\(exitCode)): \(stderr)"
        }
    }

    struct GitBinaryMissing: Error {}

    @discardableResult
    private static func runGit(_ args: [String], cwd: URL) async throws -> String {
        let result = try await runGitAllowingFailure(args, cwd: cwd)
        guard result.exitCode == 0 else {
            throw GitInvocationFailure(
                args: args,
                exitCode: result.exitCode,
                stderr: String(decoding: result.stderr, as: UTF8.self)
            )
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    private static func runGitAllowingFailure(
        _ args: [String], cwd: URL
    ) async throws -> GitSpawnResult {
        guard let binary = ToolchainLocator.git() else {
            throw GitBinaryMissing()
        }
        let runner = ProductionGitProcessRunner()
        return try await runner.run(binaryURL: binary, args: args, cwd: cwd)
    }
}
