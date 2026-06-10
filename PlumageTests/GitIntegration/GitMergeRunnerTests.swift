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
                repoURL: repoURL, defaultBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("working tree dirty surfaces parsed file list and short-circuits")
    func workingTreeDirty() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[Self.statusArgs(repoURL: repoURL)] = " M Plumage/Foo.swift\n?? Bar.txt\n"
        let runner = GitMergeRunner(runner: mock, resolveBinary: { binaryURL })

        await #expect(throws: GitMergeError.workingTreeDirty(files: ["Plumage/Foo.swift", "Bar.txt"])) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
            throws: GitMergeError.notFastForward(defaultBranch: "main", issueBranch: "issue/x")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, defaultBranch: "main",
                issueBranch: "issue/x", mode: .fastForward,
                commitSubject: nil, deleteBranch: false)
        }
        // No checkout/merge happened.
        let mutatingCalls = mock.recordedCalls.filter {
            $0.contains("checkout") || $0.contains("merge")
        }
        #expect(mutatingCalls.isEmpty)
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
            repoURL: repoURL, defaultBranch: "main",
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
            repoURL: repoURL, defaultBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(outcome.branchDeleteError == nil)
        #expect(
            mock.recordedCalls.last
                == GitMergeRunnerPreCheckTests.deleteArgs(
                    repoURL: repoURL, branch: "issue/x"))
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "--output=/tmp/x",
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
            repoURL: repoURL, defaultBranch: "main",
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
            repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
                repoURL: repoURL, defaultBranch: "main",
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
            repoURL: repoURL, defaultBranch: "main",
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
            repoURL: repoURL, defaultBranch: "main",
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
            repoURL: repoURL, defaultBranch: "main",
            issueBranch: "issue/x", mode: .fastForward,
            commitSubject: nil, deleteBranch: true)

        #expect(outcome.branchDeleteError == "error: branch 'issue/x' not fully merged")
    }
}
