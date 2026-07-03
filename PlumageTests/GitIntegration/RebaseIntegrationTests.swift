import Foundation
import Testing

@testable import Plumage

@Suite("End-to-end rebase recovery against a real tmp git repo", .tags(.integration))
struct RebaseIntegrationTests {
    @MainActor
    private func makeModel(repo: TmpGitRepo) -> IssueDetailModel {
        let mainBranch = repo.mainBranch
        return IssueDetailModel(
            specURL: repo.specURL,
            folderName: repo.folderName,
            projectURL: repo.tmpDir,
            mergeRunner: GitMergeRunner(),
            configLoader: { _ in
                ProjectConfig(
                    name: "Test", schemaVersion: 2, issueIdPadding: 5,
                    git: GitConfig(defaultBranch: mainBranch))
            }
        )
    }

    @Test(
        "diverged main fails fast-forward, then Rebase & Merge recovers end to end",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func divergedMainRecovery() async throws {
        let repo = try await TmpGitRepo.make()
        try await repo.divergeDefaultBranch()

        let model = await makeModel(repo: repo)
        await model.load()

        let firstTry = await model.mergeToTarget(
            mode: .squash, commitSubject: "Recovered change", deleteBranch: true)
        #expect(firstTry == false)
        let firstError = await model.lastMergeError
        #expect(
            firstError
                == .notFastForward(targetBranch: repo.mainBranch, issueBranch: repo.issueBranch))

        let success = await model.rebaseAndMergeToTarget(
            mode: .squash, commitSubject: "Recovered change", deleteBranch: true)

        #expect(success == true)
        let mergeError = await model.lastMergeError
        #expect(mergeError == nil)

        let branchSide = try await repo.fileContents(branch: repo.mainBranch, path: "content.txt")
        #expect(branchSide == "branch\n")
        let mainSide = try await repo.fileContents(branch: repo.mainBranch, path: "main-side.txt")
        #expect(mainSide == "main side\n")

        let subject = try await repo.commitSubject(branch: repo.mainBranch)
        #expect(subject == "Recovered change")
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == false)

        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: done"))
    }

    @Test(
        "a clean worktree owning the issue branch is removed automatically before the rebase",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func cleanWorktreeAutoRemove() async throws {
        let repo = try await TmpGitRepo.make()
        try await repo.divergeDefaultBranch()
        let worktree = try await repo.addWorktree(checkingOut: repo.issueBranch)

        let model = await makeModel(repo: repo)
        await model.load()

        let success = await model.rebaseAndMergeToTarget(
            mode: .squash, commitSubject: "Recovered change", deleteBranch: true)

        #expect(success == true)
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        let mainSide = try await repo.fileContents(branch: repo.mainBranch, path: "main-side.txt")
        #expect(mainSide == "main side\n")
        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: done"))
    }

    @Test(
        "a dirty worktree blocks the recovery, names the path, and mutates nothing",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func dirtyWorktreeBlocks() async throws {
        let repo = try await TmpGitRepo.make()
        try await repo.divergeDefaultBranch()
        let worktree = try await repo.addWorktree(checkingOut: repo.issueBranch)
        try "dirty\n".write(
            to: worktree.appendingPathComponent("content.txt"),
            atomically: true, encoding: .utf8)
        let issueHeadBefore = try await repo.headSha(branch: repo.issueBranch)

        let model = await makeModel(repo: repo)
        await model.load()

        let success = await model.rebaseAndMergeToTarget(
            mode: .squash, commitSubject: "Recovered change", deleteBranch: true)

        #expect(success == false)
        // git reports the realpath (/private/var/…) while Foundation strips
        // the /private prefix — push both sides through the same resolution.
        let mergeError = await model.lastMergeError
        if case .worktreeDirty(let path) = mergeError {
            #expect(
                URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath()
                    == worktree.resolvingSymlinksInPath())
        } else {
            Issue.record("expected worktreeDirty, got \(String(describing: mergeError))")
        }

        #expect(FileManager.default.fileExists(atPath: worktree.path))
        let issueHeadAfter = try await repo.headSha(branch: repo.issueBranch)
        #expect(issueHeadAfter == issueHeadBefore)
        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: waiting-for-review"))
    }

    @Test(
        "a provoked rebase conflict aborts, restores the original branch, and leaves no rebase in progress",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func rebaseConflictAbortsCleanly() async throws {
        let repo = try await TmpGitRepo.make()
        try await repo.divergeDefaultBranch()
        try "conflicting main edit\n".write(
            to: repo.tmpDir.appendingPathComponent("content.txt"),
            atomically: true, encoding: .utf8)
        try await repo.commitAll(message: "conflicting main edit")
        let issueHeadBefore = try await repo.headSha(branch: repo.issueBranch)

        let model = await makeModel(repo: repo)
        await model.load()

        let success = await model.rebaseAndMergeToTarget(
            mode: .squash, commitSubject: "Recovered change", deleteBranch: true)

        #expect(success == false)
        let mergeError = await model.lastMergeError
        if case .rebaseFailed = mergeError {
        } else {
            Issue.record("expected rebaseFailed, got \(String(describing: mergeError))")
        }

        let rebaseMergeDir = repo.tmpDir.appendingPathComponent(".git/rebase-merge")
        let rebaseApplyDir = repo.tmpDir.appendingPathComponent(".git/rebase-apply")
        #expect(!FileManager.default.fileExists(atPath: rebaseMergeDir.path))
        #expect(!FileManager.default.fileExists(atPath: rebaseApplyDir.path))
        let issueHeadAfter = try await repo.headSha(branch: repo.issueBranch)
        #expect(issueHeadAfter == issueHeadBefore)
        let currentBranch = try await repo.currentBranch()
        #expect(currentBranch == repo.mainBranch)
        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: waiting-for-review"))
    }
}
