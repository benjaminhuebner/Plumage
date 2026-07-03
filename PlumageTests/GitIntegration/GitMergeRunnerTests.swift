import Foundation
import Testing

@testable import Plumage

@Suite("GitMergeRunner pre-checks")
struct GitMergeRunnerPreCheckTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("git-not-found surfaces before any subprocess is spawned")
    func gitNotFoundShortCircuits() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { nil })

        await #expect(throws: GitMergeError.gitNotFound) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("failing status command throws instead of reading as a clean tree")
    func statusFailureThrows() async throws {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[Self.statusArgs(repoURL: repoURL)] = 128
        mock.stderrForArgs[Self.statusArgs(repoURL: repoURL)] = "fatal: not a git repository\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.statusCheckFailed(stderr: "fatal: not a git repository")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(mock.recordedCalls.count == 1)
    }

    @Test("working tree dirty surfaces parsed file list and short-circuits")
    func workingTreeDirty() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.statusArgs(repoURL: repoURL)] = " M Plumage/Foo.swift\n?? Bar.txt\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.workingTreeDirty(files: ["Plumage/Foo.swift", "Bar.txt"])) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(mock.recordedCalls.count == 1)
    }

    @Test("branchNotFound when rev-parse exits non-zero")
    func branchNotFound() async throws {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[Self.revParseArgs(repoURL: repoURL, branch: "issue/missing")] = 128
        mock.stderrForArgs[Self.revParseArgs(repoURL: repoURL, branch: "issue/missing")] =
            "fatal: bad revision\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchNotFound(name: "issue/missing")) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/missing", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
    }

    @Test("notFastForward when default branch is not an ancestor of issue branch")
    func notFastForward() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.revParseArgs(repoURL: repoURL, branch: "issue/x")] = "abc\n"
        mock.exitCodeForArgs[
            Self.mergeBaseArgs(
                repoURL: repoURL, base: "main", branch: "issue/x")] = 1
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.notFastForward(targetBranch: "main", issueBranch: "issue/x")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        // No checkout/merge happened.
        let mutatingCalls = mock.recordedCalls.filter {
            $0.contains("checkout") || $0.contains("merge")
        }
        #expect(mutatingCalls.isEmpty)
    }

    @Test("merge into a non-default target checks out and prechecks against it")
    func mergeIntoNonDefaultTarget() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.revParseArgs(repoURL: repoURL, branch: "issue/x")] = "abc\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        _ = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "release/1.0",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: false)

        #expect(
            mock.recordedCalls.contains(
                Self.mergeBaseArgs(repoURL: repoURL, base: "release/1.0", branch: "issue/x")))
        #expect(mock.recordedCalls.contains(Self.checkoutArgs(repoURL: repoURL, branch: "release/1.0")))
        #expect(mock.recordedCalls.contains(["-C", repoURL.path, "merge", "--ff-only", "issue/x"]))
    }

    // MARK: - Arg helpers

    static func statusArgs(repoURL: URL) -> [String] {
        ["-C", repoURL.path, "status", "--porcelain"]
    }
    static func symbolicRefArgs(repoURL: URL) -> [String] {
        ["-C", repoURL.path, "symbolic-ref", "--short", "-q", "HEAD"]
    }
    static func revParseArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "rev-parse", "--verify", branch]
    }
    static func mergeBaseArgs(repoURL: URL, base: String, branch: String) -> [String] {
        ["-C", repoURL.path, "merge-base", "--is-ancestor", base, branch]
    }
    static func checkoutArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "checkout", branch]
    }
    static func mergeArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "merge", "--ff-only", branch]
    }
    static func deleteArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "branch", "-d", branch]
    }
    static func forceDeleteArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "branch", "-D", branch]
    }
    static func squashMergeArgs(repoURL: URL, branch: String) -> [String] {
        ["-C", repoURL.path, "merge", "--squash", branch]
    }
    static func commitArgs(repoURL: URL, subject: String) -> [String] {
        ["-C", repoURL.path, "commit", "-m", subject]
    }
    static func resetMergeArgs(repoURL: URL) -> [String] {
        ["-C", repoURL.path, "reset", "--merge"]
    }
    static func worktreeListArgs(repoURL: URL) -> [String] {
        ["-C", repoURL.path, "worktree", "list", "--porcelain"]
    }
    static func worktreeRemoveArgs(repoURL: URL, path: String) -> [String] {
        ["-C", repoURL.path, "worktree", "remove", path]
    }
    static func worktreeStatusArgs(path: String) -> [String] {
        ["-C", path, "status", "--porcelain"]
    }
    static func rebaseArgs(repoURL: URL, base: String, branch: String) -> [String] {
        ["-C", repoURL.path, "rebase", base, branch]
    }
    static func rebaseAbortArgs(repoURL: URL) -> [String] {
        ["-C", repoURL.path, "rebase", "--abort"]
    }
}

@Suite("GitMergeRunner merge sequence")
struct GitMergeRunnerMergeTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    private func cleanMock() -> MockGitProcessRunner {
        let mock = MockGitProcessRunner()
        // status: empty stdout, exit 0 (default)
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.revParseArgs(repoURL: repoURL, branch: "issue/x")] = "abc\n"
        // merge-base: exit 0 (default) means is-ancestor passes
        return mock
    }

    @Test("happy path performs status → rev-parse → merge-base → checkout → merge")
    func happyPathWithoutDelete() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: false)

        #expect(outcome.branchDeleteError == nil)
        let argsSeq = mock.recordedCalls
        #expect(
            argsSeq == [
                GitMergeRunnerPreCheckTests.statusArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.revParseArgs(repoURL: repoURL, branch: "issue/x"),
                GitMergeRunnerPreCheckTests.mergeBaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"),
                GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "main"),
                GitMergeRunnerPreCheckTests.mergeArgs(repoURL: repoURL, branch: "issue/x"),
            ])
    }

    @Test("happy path with deleteBranch also runs branch -d")
    func happyPathWithDelete() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(outcome.branchDeleteError == nil)
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.deleteArgs(
                    repoURL: repoURL, branch: "issue/x"))
    }

    @Test("successful merge restores the branch the user started on")
    func successRestoresOriginalBranch() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "feature/z\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: false)

        #expect(outcome.branchDeleteError == nil)
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "feature/z"))
    }

    @Test("no restore onto the just-deleted issue branch — HEAD stays on the default branch")
    func noRestoreOntoDeletedIssueBranch() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "issue/x\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        _ = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .squash,
            commitSubject: "Subj", deleteBranch: true)

        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.forceDeleteArgs(repoURL: repoURL, branch: "issue/x"))
    }

    @Test("restore still happens when the branch delete failed (branch survives)")
    func restoreWhenDeleteFailed() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "issue/x\n"
        let deleteArgs = GitMergeRunnerPreCheckTests.deleteArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[deleteArgs] = 1
        mock.stderrForArgs[deleteArgs] = "error: branch 'issue/x' not fully merged\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(outcome.branchDeleteError != nil)
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "issue/x"))
    }

    @Test("checkoutFailed surfaces stderr")
    func checkoutFails() async throws {
        let mock = cleanMock()
        let checkoutArgs = GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "main")
        mock.exitCodeForArgs[checkoutArgs] = 1
        mock.stderrForArgs[checkoutArgs] = "error: pathspec 'main' did not match\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.checkoutFailed(stderr: "error: pathspec 'main' did not match")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
    }

    @Test("mergeFailed surfaces stderr (defensive after pre-check)")
    func mergeFails() async throws {
        let mock = cleanMock()
        let mergeArgs = GitMergeRunnerPreCheckTests.mergeArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[mergeArgs] = 128
        mock.stderrForArgs[mergeArgs] = "fatal: not possible to fast-forward\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.mergeFailed(mode: .fastForward, stderr: "fatal: not possible to fast-forward")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
    }

    @Test("failed merge restores the branch the user started on")
    func mergeFailureRestoresOriginalBranch() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "issue/x\n"
        let mergeArgs = GitMergeRunnerPreCheckTests.mergeArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[mergeArgs] = 128
        mock.stderrForArgs[mergeArgs] = "fatal: not possible to fast-forward\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.self) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "issue/x"))
    }

    @Test("failed squash commit resets the staged squash before restoring the branch")
    func squashCommitFailureResetsBeforeCheckout() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "issue/x\n"
        let commitArgs = GitMergeRunnerPreCheckTests.commitArgs(repoURL: repoURL, subject: "Subj")
        mock.exitCodeForArgs[commitArgs] = 1
        mock.stderrForArgs[commitArgs] = "gpg failed to sign the data\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.self) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .squash,
                commitSubject: "Subj", deleteBranch: false)
        }
        let tail = mock.recordedCalls.suffix(2)
        #expect(
            Array(tail) == [
                GitMergeRunnerPreCheckTests.resetMergeArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "issue/x"),
            ])
    }

    @Test("rollback skips branch restore when the merge reset fails")
    func rollbackSkipsCheckoutWhenResetFails() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL)] =
            "issue/x\n"
        let mergeArgs = GitMergeRunnerPreCheckTests.mergeArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[mergeArgs] = 128
        mock.exitCodeForArgs[GitMergeRunnerPreCheckTests.resetMergeArgs(repoURL: repoURL)] = 1
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.self) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.resetMergeArgs(repoURL: repoURL))
    }

    @Test("merge-base exit 128 reports branchNotFound, not notFastForward")
    func mergeBaseHardErrorIsNotFastForwardMisreport() async throws {
        let mock = cleanMock()
        mock.exitCodeForArgs[
            GitMergeRunnerPreCheckTests.mergeBaseArgs(
                repoURL: repoURL, base: "main", branch: "issue/x")] = 128
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchNotFound(name: "main")) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
    }

    @Test("option-shaped branch names are rejected before any subprocess runs")
    func optionShapedBranchRejected() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchNotFound(name: "--output=/tmp/x")) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "--output=/tmp/x",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("squash happy path performs checkout → merge --squash → commit -m subject")
    func squashHappyPath() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .squash,
            commitSubject: "Add squash mode to issue merge", deleteBranch: false)

        #expect(outcome.branchDeleteError == nil)
        #expect(
            mock.recordedCalls == [
                GitMergeRunnerPreCheckTests.statusArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.revParseArgs(repoURL: repoURL, branch: "issue/x"),
                GitMergeRunnerPreCheckTests.mergeBaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"),
                GitMergeRunnerPreCheckTests.symbolicRefArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.checkoutArgs(repoURL: repoURL, branch: "main"),
                GitMergeRunnerPreCheckTests.squashMergeArgs(repoURL: repoURL, branch: "issue/x"),
                GitMergeRunnerPreCheckTests.commitArgs(
                    repoURL: repoURL, subject: "Add squash mode to issue merge"),
            ])
    }

    @Test("squash passes subjects with quotes and backticks verbatim as one argument")
    func squashQuotedSubject() async throws {
        let mock = cleanMock()
        let subject = #"Fix "quoted" paths and `backtick` handling"#
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        _ = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .squash,
            commitSubject: subject, deleteBranch: false)

        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.commitArgs(repoURL: repoURL, subject: subject))
    }

    @Test("squash surfaces nothing-to-commit from commit stdout as mergeFailed")
    func squashNothingToCommit() async throws {
        let mock = cleanMock()
        let commitArgs = GitMergeRunnerPreCheckTests.commitArgs(repoURL: repoURL, subject: "No-op change")
        mock.exitCodeForArgs[commitArgs] = 1
        mock.stdoutForArgs[commitArgs] = "nothing to commit, working tree clean\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.mergeFailed(
                mode: .squash, stderr: "nothing to commit, working tree clean")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .squash,
                commitSubject: "No-op change", deleteBranch: false)
        }
    }

    @Test("squash merge step failure surfaces stderr as mergeFailed")
    func squashMergeStepFails() async throws {
        let mock = cleanMock()
        let squashArgs = GitMergeRunnerPreCheckTests.squashMergeArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[squashArgs] = 128
        mock.stderrForArgs[squashArgs] = "fatal: refusing to merge unrelated histories\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.mergeFailed(
                mode: .squash, stderr: "fatal: refusing to merge unrelated histories")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .squash,
                commitSubject: "Some change", deleteBranch: false)
        }
    }

    @Test("squash with empty subject fails before spawning merge or commit")
    func squashEmptySubject() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.mergeFailed(mode: .squash, stderr: "empty commit subject")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, targetBranch: "main",
                issueBranch: "issue/x", mode: .squash,
                commitSubject: "   ", deleteBranch: false)
        }
        // Exact-element match: "merge-base" (pre-check) is not "merge".
        let mergeOrCommit = mock.recordedCalls.filter {
            $0.contains("merge") || $0.contains("commit")
        }
        #expect(mergeOrCommit.isEmpty)
    }

    @Test("squash with deleteBranch force-deletes via branch -D")
    func squashDeleteUsesForce() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .squash,
            commitSubject: "Add squash mode", deleteBranch: true)

        #expect(outcome.branchDeleteError == nil)
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.forceDeleteArgs(repoURL: repoURL, branch: "issue/x"))
        #expect(
            !mock.recordedCalls.contains(
                GitMergeRunnerPreCheckTests.deleteArgs(repoURL: repoURL, branch: "issue/x")))
    }

    @Test("fast-forward with deleteBranch keeps the safe branch -d")
    func fastForwardDeleteStaysSafe() async throws {
        let mock = cleanMock()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        _ = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.deleteArgs(repoURL: repoURL, branch: "issue/x"))
        #expect(
            !mock.recordedCalls.contains(
                GitMergeRunnerPreCheckTests.forceDeleteArgs(repoURL: repoURL, branch: "issue/x")))
    }

    @Test("branch delete failure is non-fatal and reported in outcome")
    func branchDeleteFails() async throws {
        let mock = cleanMock()
        let deleteArgs = GitMergeRunnerPreCheckTests.deleteArgs(repoURL: repoURL, branch: "issue/x")
        mock.exitCodeForArgs[deleteArgs] = 1
        mock.stderrForArgs[deleteArgs] = "error: branch 'issue/x' not fully merged\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        let outcome = try await runner.mergeIssueBranch(
            repoURL: repoURL, targetBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(outcome.branchDeleteError == "error: branch 'issue/x' not fully merged")
    }
}

@Suite("GitMergeRunner rebase")
struct GitMergeRunnerRebaseTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")
    private let worktreePath = "/tmp/probe-repo-issue-x"

    private typealias Args = GitMergeRunnerPreCheckTests

    private func cleanMock(currentBranch: String = "main") -> MockGitProcessRunner {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Args.revParseArgs(repoURL: repoURL, branch: "issue/x")] = "abc\n"
        mock.stdoutForArgs[Args.symbolicRefArgs(repoURL: repoURL)] = "\(currentBranch)\n"
        return mock
    }

    private func worktreeListPorcelain(_ entries: [(path: String, branch: String)]) -> String {
        entries
            .map { "worktree \($0.path)\nHEAD abc123\nbranch refs/heads/\($0.branch)\n" }
            .joined(separator: "\n")
    }

    @Test("happy path rebases and restores the original branch")
    func happyPathRestoresOriginalBranch() async throws {
        let mock = cleanMock(currentBranch: "main")
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        try await runner.rebaseIssueBranch(
            repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")

        #expect(
            mock.recordedCalls == [
                Args.statusArgs(repoURL: repoURL),
                Args.revParseArgs(repoURL: repoURL, branch: "issue/x"),
                Args.worktreeListArgs(repoURL: repoURL),
                Args.symbolicRefArgs(repoURL: repoURL),
                Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"),
                Args.checkoutArgs(repoURL: repoURL, branch: "main"),
            ])
    }

    @Test("no branch restore when the user already sits on the issue branch")
    func noRestoreWhenOnIssueBranch() async throws {
        let mock = cleanMock(currentBranch: "issue/x")
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        try await runner.rebaseIssueBranch(
            repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")

        #expect(
            mock.recordedCalls.last
                == Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"))
    }

    @Test("failing status command throws instead of reading as a clean tree")
    func statusFailureThrows() async throws {
        let mock = cleanMock()
        mock.exitCodeForArgs[Args.statusArgs(repoURL: repoURL)] = 128
        mock.stderrForArgs[Args.statusArgs(repoURL: repoURL)] = "fatal: not a git repository\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.statusCheckFailed(stderr: "fatal: not a git repository")
        ) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        #expect(mock.recordedCalls.count == 1)
    }

    @Test("dirty working tree short-circuits before any mutation")
    func dirtyTreeShortCircuits() async throws {
        let mock = cleanMock()
        mock.stdoutForArgs[Args.statusArgs(repoURL: repoURL)] = " M Plumage/Foo.swift\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.workingTreeDirty(files: ["Plumage/Foo.swift"])) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        #expect(mock.recordedCalls.count == 1)
    }

    @Test("missing issue branch reports branchNotFound")
    func missingBranch() async throws {
        let mock = cleanMock()
        mock.exitCodeForArgs[Args.revParseArgs(repoURL: repoURL, branch: "issue/x")] = 128
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchNotFound(name: "issue/x")) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
    }

    @Test("conflict aborts the rebase and restores the original branch")
    func conflictAbortsAndRestores() async throws {
        let mock = cleanMock(currentBranch: "main")
        let rebaseArgs = Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x")
        mock.exitCodeForArgs[rebaseArgs] = 1
        mock.stderrForArgs[rebaseArgs] = "CONFLICT (content): Merge conflict in Foo.swift\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(
            throws: GitMergeError.rebaseFailed(
                stderr: "CONFLICT (content): Merge conflict in Foo.swift")
        ) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        let tail = Array(mock.recordedCalls.suffix(2))
        #expect(
            tail == [
                Args.rebaseAbortArgs(repoURL: repoURL),
                Args.checkoutArgs(repoURL: repoURL, branch: "main"),
            ])
    }

    @Test(
        "worktree-blocked stderr maps to branchCheckedOutElsewhere without an abort",
        arguments: [
            "fatal: 'issue/x' is already used by worktree at '/tmp/wt'",
            "fatal: 'issue/x' is already checked out at '/tmp/wt'",
        ])
    func worktreeBlockedStderr(variant: String) async throws {
        let mock = cleanMock()
        let rebaseArgs = Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x")
        mock.exitCodeForArgs[rebaseArgs] = 128
        mock.stderrForArgs[rebaseArgs] = variant + "\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchCheckedOutElsewhere(branch: "issue/x")) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        #expect(!mock.recordedCalls.contains(Args.rebaseAbortArgs(repoURL: repoURL)))
    }

    @Test("empty rebase stderr falls back to stdout")
    func emptyStderrFallsBackToStdout() async throws {
        let mock = cleanMock()
        let rebaseArgs = Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x")
        mock.exitCodeForArgs[rebaseArgs] = 1
        mock.stdoutForArgs[rebaseArgs] = "could not apply abc123\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.rebaseFailed(stderr: "could not apply abc123")) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
    }

    @Test("git-not-found surfaces before any subprocess is spawned")
    func gitNotFoundShortCircuits() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { nil })

        await #expect(throws: GitMergeError.gitNotFound) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("option-shaped branch names are rejected before any subprocess runs")
    func optionShapedBranchRejected() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchNotFound(name: "--upload-pack=evil")) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "--upload-pack=evil")
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("a clean worktree owning the branch is removed before the rebase")
    func cleanWorktreeRemovedBeforeRebase() async throws {
        let mock = cleanMock(currentBranch: "main")
        mock.stdoutForArgs[Args.worktreeListArgs(repoURL: repoURL)] = worktreeListPorcelain([
            (path: repoURL.path, branch: "main"),
            (path: worktreePath, branch: "issue/x"),
        ])
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        try await runner.rebaseIssueBranch(
            repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")

        let calls = mock.recordedCalls
        let removeIndex = try #require(
            calls.firstIndex(of: Args.worktreeRemoveArgs(repoURL: repoURL, path: worktreePath)))
        let rebaseIndex = try #require(
            calls.firstIndex(of: Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x")))
        #expect(removeIndex < rebaseIndex)
    }

    @Test("a dirty worktree blocks with worktreeDirty and no git mutation")
    func dirtyWorktreeBlocks() async throws {
        let mock = cleanMock(currentBranch: "main")
        mock.stdoutForArgs[Args.worktreeListArgs(repoURL: repoURL)] = worktreeListPorcelain([
            (path: worktreePath, branch: "issue/x")
        ])
        mock.stdoutForArgs[Args.worktreeStatusArgs(path: worktreePath)] = " M content.txt\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.worktreeDirty(path: worktreePath)) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        let mutating = mock.recordedCalls.filter {
            $0.contains("rebase") || $0.contains("remove") || $0.contains("checkout")
        }
        #expect(mutating.isEmpty)
    }

    @Test("a failed worktree remove degrades to branchCheckedOutElsewhere")
    func failedWorktreeRemoveDegrades() async throws {
        let mock = cleanMock(currentBranch: "main")
        mock.stdoutForArgs[Args.worktreeListArgs(repoURL: repoURL)] = worktreeListPorcelain([
            (path: worktreePath, branch: "issue/x")
        ])
        mock.exitCodeForArgs[Args.worktreeRemoveArgs(repoURL: repoURL, path: worktreePath)] = 128
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.branchCheckedOutElsewhere(branch: "issue/x")) {
            try await runner.rebaseIssueBranch(
                repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")
        }
        #expect(
            !mock.recordedCalls.contains(
                Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x")))
    }

    @Test("the branch checked out in the repo's own checkout is not treated as blocking")
    func ownCheckoutIsNotBlocking() async throws {
        let mock = cleanMock(currentBranch: "issue/x")
        mock.stdoutForArgs[Args.worktreeListArgs(repoURL: repoURL)] = worktreeListPorcelain([
            (path: repoURL.path, branch: "issue/x")
        ])
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        try await runner.rebaseIssueBranch(
            repoURL: repoURL, targetBranch: "main", issueBranch: "issue/x")

        let worktreeMutations = mock.recordedCalls.filter { $0.contains("remove") }
        #expect(worktreeMutations.isEmpty)
        #expect(
            mock.recordedCalls.last
                == Args.rebaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"))
    }
}

@Suite("GitMergeError messages")
struct GitMergeErrorMessageTests {
    @Test("notFastForward points at the Rebase & Merge button")
    func notFastForwardMentionsButton() {
        let message = GitMergeError.notFastForward(
            targetBranch: "main", issueBranch: "issue/x"
        ).displayMessage
        #expect(message.contains("main"))
        #expect(message.contains("issue/x"))
        #expect(message.contains("Use Rebase & Merge"))
    }

    @Test("rebaseFailed carries stderr and explains manual resolution")
    func rebaseFailedMessage() {
        let message = GitMergeError.rebaseFailed(
            stderr: "CONFLICT (content): Merge conflict in Foo.swift"
        ).displayMessage
        #expect(message.contains("CONFLICT (content): Merge conflict in Foo.swift"))
        #expect(message.contains("aborted"))
        #expect(message.contains("manually"))
    }

    @Test("branchCheckedOutElsewhere names the branch")
    func branchCheckedOutElsewhereMessage() {
        let message = GitMergeError.branchCheckedOutElsewhere(branch: "issue/x").displayMessage
        #expect(message.contains("issue/x"))
        #expect(message.contains("worktree"))
    }

    @Test("worktreeDirty names the path and asks to commit or discard")
    func worktreeDirtyMessage() {
        let message = GitMergeError.worktreeDirty(path: "/tmp/Proj-issue-x").displayMessage
        #expect(message.contains("/tmp/Proj-issue-x"))
        #expect(message.contains("uncommitted"))
        #expect(message.contains("Commit or discard"))
    }
}
