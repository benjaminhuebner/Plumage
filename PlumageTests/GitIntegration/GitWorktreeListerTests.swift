import Foundation
import Testing

@testable import Plumage

struct GitWorktreeListerTests {
    @Test("porcelain output parses paths, branches, and detached state")
    func parsePorcelain() {
        let porcelain = """
            worktree /Users/dev/Projects/Sample
            HEAD 08ec670f5864c03fccac8842a1e1e99c0df2287e
            branch refs/heads/main

            worktree /Users/dev/Projects/Sample-00042-feature
            HEAD b61854e1f0c2a9d3e4f5a6b7c8d9e0f1a2b3c4d5
            branch refs/heads/issue/00042-feature

            worktree /Users/dev/Projects/Sample-detached
            HEAD 4a3ad96b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f
            detached
            """

        let worktrees = GitWorktreeLister.parse(porcelain: porcelain)

        #expect(worktrees.count == 3)
        #expect(worktrees[0].path.path() == "/Users/dev/Projects/Sample/")
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[1].branch == "issue/00042-feature")
        #expect(worktrees[2].path.lastPathComponent == "Sample-detached")
        #expect(worktrees[2].branch == nil)
    }

    @Test("empty output yields no worktrees")
    func parseEmpty() {
        #expect(GitWorktreeLister.parse(porcelain: "").isEmpty)
    }

    @Test("paths containing spaces survive parsing")
    func parsePathWithSpaces() {
        let porcelain = """
            worktree /Users/dev/My Projects/Sample App
            HEAD 08ec670f5864c03fccac8842a1e1e99c0df2287e
            branch refs/heads/main
            """

        let worktrees = GitWorktreeLister.parse(porcelain: porcelain)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].path.lastPathComponent == "Sample App")
    }

    @Test("non-zero exit throws listFailed with stderr")
    func nonZeroExitThrows() async {
        let mock = MockGitProcessRunner()
        let args = ["worktree", "list", "--porcelain"]
        mock.exitCodeForArgs = [args: 128]
        mock.stderrForArgs = [args: "fatal: not a git repository"]
        let lister = GitWorktreeLister(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        await #expect(throws: GitWorktreeListError.listFailed(stderr: "fatal: not a git repository")) {
            _ = try await lister.worktrees(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test("missing git binary throws gitNotFound")
    func missingBinaryThrows() async {
        let lister = GitWorktreeLister(runner: MockGitProcessRunner(), resolveBinary: { nil })

        await #expect(throws: GitWorktreeListError.gitNotFound) {
            _ = try await lister.worktrees(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test(
        "real repo with a secondary worktree enumerates both",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func realWorktreeEnumeration() async throws {
        let repo = try await TmpGitRepo.make()
        let secondary = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeListerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: secondary) }

        let binary = try #require(ToolchainLocator.git())
        let runner = ProductionGitProcessRunner()
        let add = try await runner.run(
            binaryURL: binary,
            args: ["worktree", "add", "--detach", secondary.path(), repo.mainBranch],
            cwd: repo.tmpDir
        )
        try #require(add.exitCode == 0, "worktree add failed")

        let worktrees = try await GitWorktreeLister().worktrees(repoURL: repo.tmpDir)

        #expect(worktrees.count == 2)
        let primary = try #require(worktrees.first)
        #expect(primary.path.standardizedFileURL.lastPathComponent == repo.tmpDir.lastPathComponent)
        let added = try #require(worktrees.last)
        #expect(added.branch == nil)
        #expect(added.path.standardizedFileURL.lastPathComponent == secondary.lastPathComponent)
    }
}
