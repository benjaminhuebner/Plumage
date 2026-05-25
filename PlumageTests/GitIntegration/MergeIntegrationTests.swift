import Foundation
import Testing

@testable import Plumage

@Suite("End-to-end merge against a real tmp git repo")
@MainActor
struct MergeIntegrationTests {
    @Test("happy path merges issue branch into main, flips spec status, deletes branch, signals kanban")
    func happyPathMergesAndSignals() async throws {
        let repo = try await TmpGitRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.tmpDir) }

        let issueBranchHead = try await repo.headSha(branch: repo.issueBranch)

        let model = IssueDetailModel(
            specURL: repo.specURL,
            folderName: repo.folderName,
            projectURL: repo.tmpDir,
            mergeRunner: GitMergeRunner(),
            configLoader: { _ in
                ProjectConfig(
                    name: "Test", schemaVersion: 2, issueIdPadding: 5,
                    git: GitConfig(defaultBranch: repo.mainBranch))
            }
        )
        await model.load()
        let kanban = ProjectKanbanModel()

        let success = await model.mergeToMain(deleteBranch: true)
        // Mirror the IssueDetailView wiring — on success, fire the kanban
        // signal so the auto-dismiss observer would trigger in real use.
        if success, let folderName = model.folderName {
            kanban.signalMergeCompleted(folderName: folderName)
        }

        // 1. mergeToMain reported success.
        #expect(success == true)
        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeCriticalError == nil)
        #expect(model.lastMergeNotice == nil)

        // 2. main HEAD == old issue-branch HEAD (fast-forward).
        let mainHead = try await repo.headSha(branch: repo.mainBranch)
        #expect(mainHead == issueBranchHead)

        // 3. Issue branch is gone.
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == false)

        // 4. Spec status flipped to done on disk.
        let onDisk = try String(contentsOf: repo.specURL, encoding: .utf8)
        #expect(onDisk.contains("status: done"))
        #expect(model.issue?.status == .done)

        // 5. Kanban signal fired with the right folder name.
        #expect(kanban.lastMergeCompleted == repo.folderName)
    }

    @Test("delete-branch=false keeps the branch but still flips spec status")
    func keepsBranchWhenDeleteFalse() async throws {
        let repo = try await TmpGitRepo.make()
        defer { try? FileManager.default.removeItem(at: repo.tmpDir) }

        let model = IssueDetailModel(
            specURL: repo.specURL,
            folderName: repo.folderName,
            projectURL: repo.tmpDir,
            mergeRunner: GitMergeRunner(),
            configLoader: { _ in
                ProjectConfig(
                    name: "Test", schemaVersion: 2, issueIdPadding: 5,
                    git: GitConfig(defaultBranch: repo.mainBranch))
            }
        )
        await model.load()

        let success = await model.mergeToMain(deleteBranch: false)

        #expect(success == true)
        #expect(model.issue?.status == .done)
        let branchPresent = await repo.branchExists(repo.issueBranch)
        #expect(branchPresent == true)
    }
}
