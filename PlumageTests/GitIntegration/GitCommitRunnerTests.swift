import Foundation
import Testing

@testable import Plumage

@Suite("GitCommitRunner")
struct GitCommitRunnerTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("empty message throws before any subprocess call")
    func emptyMessageRejects() async {
        let mock = MockGitProcessRunner()
        let runner = GitCommitRunner(runner: mock, resolveBinary: { self.binaryURL })
        await #expect(throws: GitCommitError.emptyMessage) {
            try await runner.commit(repoURL: self.repoURL, message: "")
        }
        await #expect(throws: GitCommitError.emptyMessage) {
            try await runner.commit(repoURL: self.repoURL, message: "   \n  ")
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("gitNotFound short-circuits before any subprocess call")
    func gitNotFoundShortCircuits() async {
        let mock = MockGitProcessRunner()
        let runner = GitCommitRunner(runner: mock, resolveBinary: { nil })
        await #expect(throws: GitCommitError.gitNotFound) {
            try await runner.commit(repoURL: self.repoURL, message: "real message")
        }
    }

    @Test("success path passes -m <message>")
    func successPath() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitCommitRunner(runner: mock, resolveBinary: { self.binaryURL })
        try await runner.commit(repoURL: repoURL, message: "feat: add thing")
        let expected = ["-C", repoURL.path, "commit", "-m", "feat: add thing"]
        #expect(mock.recordedCalls == [expected])
    }

    @Test("nothing-to-commit stderr is mapped to typed error")
    func nothingToCommit() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "commit", "-m", "msg"]
        mock.exitCodeForArgs[args] = 1
        mock.stdoutForArgs[args] = "On branch main\nnothing to commit, working tree clean\n"
        let runner = GitCommitRunner(runner: mock, resolveBinary: { self.binaryURL })

        await #expect(throws: GitCommitError.self) {
            try await runner.commit(repoURL: self.repoURL, message: "msg")
        }
        // Specifically the typed nothingToCommit variant — not nonZeroExit.
        do {
            try await runner.commit(repoURL: repoURL, message: "msg")
            Issue.record("expected commit to throw")
        } catch let GitCommitError.nothingToCommit(stderr) {
            #expect(stderr.isEmpty || stderr.contains("nothing"))
        } catch {
            Issue.record("expected nothingToCommit, got \(error)")
        }
    }

    @Test("generic non-zero exit surfaces as nonZeroExit")
    func genericFailure() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "commit", "-m", "msg"]
        mock.exitCodeForArgs[args] = 1
        mock.stderrForArgs[args] = "fatal: pathspec error\n"
        let runner = GitCommitRunner(runner: mock, resolveBinary: { self.binaryURL })

        do {
            try await runner.commit(repoURL: repoURL, message: "msg")
            Issue.record("expected commit to throw")
        } catch let GitCommitError.nonZeroExit(code, stderr) {
            #expect(code == 1)
            #expect(stderr.contains("pathspec"))
        } catch {
            Issue.record("expected nonZeroExit, got \(error)")
        }
    }
}
