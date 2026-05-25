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
                issueBranch: "issue/x", deleteBranch: false)
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
                issueBranch: "issue/x", deleteBranch: false)
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
                issueBranch: "issue/missing", deleteBranch: false)
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
                issueBranch: "issue/x", deleteBranch: false)
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
            issueBranch: "issue/x", deleteBranch: false)

        #expect(outcome.branchDeleteError == nil)
        let argsSeq = mock.recordedCalls
        #expect(
            argsSeq == [
                GitMergeRunnerPreCheckTests.statusArgs(repoURL: repoURL),
                GitMergeRunnerPreCheckTests.revParseArgs(repoURL: repoURL, branch: "issue/x"),
                GitMergeRunnerPreCheckTests.mergeBaseArgs(repoURL: repoURL, base: "main", branch: "issue/x"),
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
            issueBranch: "issue/x", deleteBranch: true)

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
                issueBranch: "issue/x", deleteBranch: false)
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
            throws: GitMergeError.mergeFailed(stderr: "fatal: not possible to fast-forward")
        ) {
            _ = try await runner.mergeIssueBranch(
                repoURL: repoURL, defaultBranch: "main",
                issueBranch: "issue/x", deleteBranch: false)
        }
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
            issueBranch: "issue/x", deleteBranch: true)

        #expect(outcome.branchDeleteError == "error: branch 'issue/x' not fully merged")
    }
}
