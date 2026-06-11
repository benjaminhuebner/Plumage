import Foundation
import Testing

@testable import Plumage

@Suite("Merge worktree auto-cleanup", .tags(.integration))
struct MergeWorktreeCleanupTests {
    private func addWorktree(repo: TmpGitRepo, at target: URL) async throws {
        let binary = try #require(ToolchainLocator.git())
        let runner = ProductionGitProcessRunner()
        // Free the issue branch first — TmpGitRepo leaves it checked out in
        // the primary, and a branch can only be checked out once per repo.
        let checkout = try await runner.run(
            binaryURL: binary, args: ["checkout", repo.mainBranch], cwd: repo.tmpDir)
        try #require(checkout.exitCode == 0)
        let add = try await runner.run(
            binaryURL: binary,
            args: ["worktree", "add", target.path(), repo.issueBranch],
            cwd: repo.tmpDir
        )
        try #require(add.exitCode == 0)
    }

    @Test(
        "clean worktree is removed, then the branch is deleted",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func cleanWorktreeRemovedAndBranchDeleted() async throws {
        let repo = try await TmpGitRepo.make()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MergeWorktreeCleanupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }
        try await addWorktree(repo: repo, at: target)

        let outcome = try await GitMergeRunner().mergeIssueBranch(
            repoURL: repo.tmpDir,
            defaultBranch: repo.mainBranch,
            issueBranch: repo.issueBranch,
            mode: .squash,
            commitSubject: "Squash the issue",
            deleteBranch: true
        )

        #expect(outcome.branchDeleteError == nil)
        #expect(outcome.worktreeCleanupNotice == nil)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        let branchStillThere = await repo.branchExists(repo.issueBranch)
        #expect(branchStillThere == false)
    }

    @Test(
        "dirty worktree keeps worktree and branch, with a notice",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func dirtyWorktreeKeepsEverything() async throws {
        let repo = try await TmpGitRepo.make()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MergeWorktreeCleanupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }
        try await addWorktree(repo: repo, at: target)
        try "wip".write(
            to: target.appendingPathComponent("wip.txt"), atomically: true, encoding: .utf8)

        let outcome = try await GitMergeRunner().mergeIssueBranch(
            repoURL: repo.tmpDir,
            defaultBranch: repo.mainBranch,
            issueBranch: repo.issueBranch,
            mode: .squash,
            commitSubject: "Squash the issue",
            deleteBranch: true
        )

        #expect(outcome.worktreeCleanupNotice?.contains("uncommitted changes") == true)
        #expect(outcome.branchDeleteError == nil)
        #expect(FileManager.default.fileExists(atPath: target.path))
        let branchStillThere = await repo.branchExists(repo.issueBranch)
        #expect(branchStillThere)
    }
}
