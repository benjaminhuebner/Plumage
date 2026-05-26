import Foundation
import Testing

@testable import Plumage

@Suite("GitCurrentBranchRunner")
struct GitCurrentBranchRunnerTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    private var symbolicArgs: [String] {
        ["-C", repoURL.path, "symbolic-ref", "--short", "HEAD"]
    }

    private var revParseArgs: [String] {
        ["-C", repoURL.path, "rev-parse", "--short", "HEAD"]
    }

    @Test("gitNotFound short-circuits before any subprocess call")
    func gitNotFoundShortCircuits() async {
        let mock = MockGitProcessRunner()
        let runner = GitCurrentBranchRunner(runner: mock, resolveBinary: { nil })
        await #expect(throws: GitCurrentBranchError.gitNotFound) {
            _ = try await runner.run(repoURL: self.repoURL)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("symbolic-ref success yields .branch")
    func symbolicRefSuccess() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[symbolicArgs] = "main\n"
        let runner = GitCurrentBranchRunner(runner: mock, resolveBinary: { self.binaryURL })
        let state = try await runner.run(repoURL: repoURL)
        #expect(state == .branch("main"))
        // No fallback rev-parse needed when symbolic-ref succeeds.
        #expect(mock.recordedCalls.count == 1)
    }

    @Test("symbolic-ref failure + rev-parse success yields .detached")
    func detachedHeadFallback() async throws {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[symbolicArgs] = 128
        mock.stderrForArgs[symbolicArgs] = "fatal: ref HEAD is not a symbolic ref\n"
        mock.stdoutForArgs[revParseArgs] = "a1b2c3d\n"
        let runner = GitCurrentBranchRunner(runner: mock, resolveBinary: { self.binaryURL })

        let state = try await runner.run(repoURL: repoURL)
        #expect(state == .detached(sha: "a1b2c3d"))
        #expect(mock.recordedCalls.count == 2)
    }

    @Test("both calls fail with 'not a git repository' yields .notAGitRepo")
    func notAGitRepo() async {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[symbolicArgs] = 128
        mock.stderrForArgs[symbolicArgs] = "fatal: not a git repository\n"
        mock.exitCodeForArgs[revParseArgs] = 128
        mock.stderrForArgs[revParseArgs] = "fatal: not a git repository (or any parent up to mount point)\n"
        let runner = GitCurrentBranchRunner(runner: mock, resolveBinary: { self.binaryURL })

        await #expect(throws: GitCurrentBranchError.notAGitRepo) {
            _ = try await runner.run(repoURL: self.repoURL)
        }
    }
}
