import Foundation
import Testing

@testable import Plumage

@Suite("End-to-end merge against a real tmp git repo", .tags(.integration))
struct MergeIntegrationTests {
    @Test(
        "happy path merges issue branch into main, flips spec status, deletes branch, signals kanban",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func happyPathMergesAndSignals() async throws {
        let repo = try await TmpGitRepo.make()
        let issueBranchHead = try await repo.headSha(branch: repo.issueBranch)
        let mainBranch = repo.mainBranch

        let model = await IssueDetailModel(
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
        await model.load()
        let kanban = await ProjectKanbanModel()

        let success = await model.mergeToTarget(mode: .fastForward, commitSubject: nil, deleteBranch: true)
        // Mirror the IssueDetailView wiring — on success, fire the kanban
        // signal so the auto-dismiss observer would trigger in real use.
        if success, let folderName = await model.folderName {
            await kanban.signalMergeCompleted(folderName: folderName)
        }

        // 1. mergeToTarget reported success.
        #expect(success == true)
        let mergeError = await model.lastMergeError
        let mergeCritical = await model.lastMergeCriticalError
        let mergeNotice = await model.lastMergeNotice
        #expect(mergeError == nil)
        #expect(mergeCritical == nil)
        #expect(mergeNotice == nil)

        // 2. main HEAD == old issue-branch HEAD (fast-forward).
        let mainHead = try await repo.headSha(branch: repo.mainBranch)
        #expect(mainHead == issueBranchHead)

        // 3. Issue branch is gone.
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == false)

        // 4. Spec status flipped to done on disk.
        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: done"))
        let modelStatus = await model.issue?.status
        #expect(modelStatus == .done)

        // 5. Kanban signal fired with the right folder name.
        let lastMerge = await kanban.lastMergeCompleted
        #expect(lastMerge == repo.folderName)
    }

    @Test(
        "merge writes a real merged.diff snapshot via the production capture path",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func mergeWritesRealSnapshot() async throws {
        let repo = try await TmpGitRepo.make()
        let mainBranch = repo.mainBranch

        // No mergedDiffCapturer/mergedDiffWriter override → exercises the real
        // GitDiffRunner capture + real file write (the path unit tests stub out).
        let model = await IssueDetailModel(
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
        await model.load()

        let success = await model.mergeToTarget(
            mode: .fastForward, commitSubject: nil, deleteBranch: true)
        #expect(success == true)

        // The branch is gone — the snapshot must have been captured before that.
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == false)

        // merged.diff exists and holds the branch's committed contribution.
        let snapshotURL = IssueLayout.mergedDiffURL(
            in: repo.tmpDir, folderName: repo.folderName)
        let snapshot = try String(contentsOf: snapshotURL, encoding: .utf8)
        #expect(snapshot.contains("diff --git"))
        #expect(snapshot.contains("content.txt"))
        #expect(snapshot.contains("+branch"))

        // And it parses to the file DiffTabModel would render post-merge.
        let parsed = DiffParser.parse(unifiedDiff: snapshot)
        #expect(parsed.count == 1)
        #expect(parsed.first?.path == "content.txt")
    }

    @Test(
        "squash mode lands exactly one new commit on main with the subject and force-deletes the branch",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func squashMergeProducesSingleCommit() async throws {
        let repo = try await TmpGitRepo.make()
        let mainBranch = repo.mainBranch
        let countBefore = try await repo.commitCount(branch: mainBranch)

        let model = await IssueDetailModel(
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
        await model.load()

        let success = await model.mergeToTarget(
            mode: .squash, commitSubject: "Add squash mode to issue merge", deleteBranch: true)

        #expect(success == true)
        let countAfter = try await repo.commitCount(branch: mainBranch)
        #expect(countAfter == countBefore + 1)
        let subject = try await repo.commitSubject(branch: mainBranch)
        #expect(subject == "Add squash mode to issue merge")
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == false)
        let modelStatus = await model.issue?.status
        #expect(modelStatus == .done)
    }

    @Test(
        "delete-branch=false keeps the branch but still flips spec status",
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func keepsBranchWhenDeleteFalse() async throws {
        let repo = try await TmpGitRepo.make()
        let mainBranch = repo.mainBranch

        let model = await IssueDetailModel(
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
        await model.load()

        let success = await model.mergeToTarget(mode: .fastForward, commitSubject: nil, deleteBranch: false)

        #expect(success == true)
        let modelStatus = await model.issue?.status
        #expect(modelStatus == .done)
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == true)
    }
}
