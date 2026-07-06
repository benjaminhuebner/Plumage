import Foundation
import Testing

@testable import Plumage

nonisolated struct RecordedBranchMerge: Equatable, Sendable {
    let repoPath: String
    let targetBranch: String
    let sourceBranch: String
    let mode: GitMergeMode
    let commitSubject: String?
    let deleteBranch: Bool
}

nonisolated struct RecordingBranchMergeRunner: GitMergeRunning {
    let calls: LockedBox<[RecordedBranchMerge]>
    var outcome: GitMergeOutcome = GitMergeOutcome(branchDeleteError: nil)
    var error: GitMergeError?

    func mergeBranch(
        repoURL: URL,
        targetBranch: String,
        sourceBranch: String,
        mode: GitMergeMode,
        commitSubject: String?,
        deleteBranch: Bool
    ) async throws -> GitMergeOutcome {
        calls.mutate {
            $0.append(
                RecordedBranchMerge(
                    repoPath: repoURL.path,
                    targetBranch: targetBranch,
                    sourceBranch: sourceBranch,
                    mode: mode,
                    commitSubject: commitSubject,
                    deleteBranch: deleteBranch))
        }
        if let error { throw error }
        return outcome
    }

    func rebaseIssueBranch(
        repoURL: URL,
        targetBranch: String,
        issueBranch: String
    ) async throws {}
}

@Suite("ProjectGitModel branch merge")
@MainActor
struct ProjectGitModelMergeTests {
    private nonisolated static let repoURL = URL(filePath: "/tmp/probe-repo")
    private nonisolated static let fakeBinary = URL(filePath: "/usr/bin/git")
    private nonisolated static let listArgs = [
        "-C", repoURL.path, "for-each-ref", "--format=%(refname:short)", "refs/heads/",
    ]

    private func makeModel(
        runner: RecordingBranchMergeRunner,
        branches: [String] = ["feature/a", "feature/b", "main"]
    ) async -> ProjectGitModel {
        let processMock = MockGitProcessRunner()
        processMock.stdoutForArgs[Self.listArgs] = branches.joined(separator: "\n") + "\n"
        let model = ProjectGitModel(
            branchLister: GitBranchLister(
                runner: processMock, resolveBinary: { Self.fakeBinary }),
            mergeRunner: runner)
        model._setRepoURLForTesting(Self.repoURL)
        await model.loadBranches()
        return model
    }

    @Test("requestBranchMerge sets the pending request and clears stale state")
    func requestSetsPending() async {
        let runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        let model = await makeModel(runner: runner)

        model.requestBranchMerge(source: "feature/a", target: "main")

        #expect(model.pendingBranchMerge == BranchMergeRequest(source: "feature/a", target: "main"))
    }

    @Test("self-drop request is a no-op")
    func selfDropRequestIsNoOp() async {
        let runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        let model = await makeModel(runner: runner)

        model.requestBranchMerge(source: "main", target: "main")

        #expect(model.pendingBranchMerge == nil)
    }

    @Test("a request naming an unknown branch is rejected")
    func unknownBranchRequestIsRejected() async {
        let runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        let model = await makeModel(runner: runner)

        model.requestBranchMerge(source: "ghost/branch", target: "main")
        model.requestBranchMerge(source: "feature/a", target: "ghost/branch")

        #expect(model.pendingBranchMerge == nil)
    }

    @Test("mergeBranch passes source, target, mode, subject, and delete through to the runner")
    func mergePassesThrough() async {
        let calls = LockedBox<[RecordedBranchMerge]>(value: [])
        let runner = RecordingBranchMergeRunner(calls: calls)
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .squash,
            subject: "Merge feature/a into main", deleteSource: true)

        #expect(merged)
        #expect(
            calls.value == [
                RecordedBranchMerge(
                    repoPath: Self.repoURL.path,
                    targetBranch: "main",
                    sourceBranch: "feature/a",
                    mode: .squash,
                    commitSubject: "Merge feature/a into main",
                    deleteBranch: true)
            ])
        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeNotice == nil)
        #expect(model.isMerging == false)
    }

    @Test("merging a branch onto itself refuses without touching the runner")
    func selfMergeRefuses() async {
        let calls = LockedBox<[RecordedBranchMerge]>(value: [])
        let runner = RecordingBranchMergeRunner(calls: calls)
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "main", target: "main", mode: .fastForward,
            subject: nil, deleteSource: false)

        #expect(merged == false)
        #expect(calls.value.isEmpty)
    }

    @Test("a dirty working tree surfaces as lastMergeError")
    func dirtyTreeSurfacesError() async {
        var runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        runner.error = .workingTreeDirty(files: ["Plumage/Foo.swift"])
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .fastForward,
            subject: nil, deleteSource: false)

        #expect(merged == false)
        #expect(model.lastMergeError == .workingTreeDirty(files: ["Plumage/Foo.swift"]))
        #expect(model.isMerging == false)
    }

    @Test("notFastForward surfaces as lastMergeError")
    func notFastForwardSurfacesError() async {
        var runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        runner.error = .notFastForward(targetBranch: "main", issueBranch: "feature/a")
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .fastForward,
            subject: nil, deleteSource: false)

        #expect(merged == false)
        #expect(
            model.lastMergeError
                == .notFastForward(targetBranch: "main", issueBranch: "feature/a"))
    }

    @Test("a failed source delete is non-fatal: merge succeeds with a notice")
    func deleteFailureIsNonFatal() async {
        var runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        runner.outcome = GitMergeOutcome(branchDeleteError: "not fully merged")
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .fastForward,
            subject: nil, deleteSource: true)

        #expect(merged)
        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeNotice == "Merge succeeded, but branch was not deleted: not fully merged")
    }

    @Test("a kept worktree is non-fatal: merge succeeds with a notice")
    func worktreeCleanupNoticeIsNonFatal() async {
        var runner = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        runner.outcome = GitMergeOutcome(
            branchDeleteError: nil,
            worktreeCleanupNotice: "the worktree at /tmp/wt has uncommitted changes — worktree and branch were kept")
        let model = await makeModel(runner: runner)

        let merged = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .fastForward,
            subject: nil, deleteSource: true)

        #expect(merged)
        #expect(model.lastMergeNotice?.contains("worktree and branch were kept") == true)
    }

    @Test("a new merge clears the previous error and notice")
    func newMergeClearsStaleState() async {
        var failing = RecordingBranchMergeRunner(calls: LockedBox(value: []))
        failing.error = .workingTreeDirty(files: ["x"])
        let model = await makeModel(runner: failing)
        _ = await model.mergeBranch(
            source: "feature/a", target: "main", mode: .fastForward,
            subject: nil, deleteSource: false)
        #expect(model.lastMergeError != nil)

        model.requestBranchMerge(source: "feature/a", target: "main")

        #expect(model.lastMergeError == nil)
        #expect(model.lastMergeNotice == nil)
    }
}
