import Foundation
import Testing

@testable import Plumage

@Suite("GitStageRunner")
struct GitStageRunnerTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("gitNotFound short-circuits")
    func gitNotFoundShortCircuits() async {
        let mock = MockGitProcessRunner()
        let runner = GitStageRunner(runner: mock, resolveBinary: { nil })
        await #expect(throws: GitCommandError.gitNotFound) {
            try await runner.stage(repoURL: self.repoURL, paths: ["a"])
        }
    }

    @Test("empty path list throws emptyPathList")
    func emptyPaths() async {
        let mock = MockGitProcessRunner()
        let runner = GitStageRunner(runner: mock, resolveBinary: { self.binaryURL })
        await #expect(throws: GitStageError.emptyPathList) {
            try await runner.stage(repoURL: self.repoURL, paths: [])
        }
        await #expect(throws: GitStageError.emptyPathList) {
            try await runner.unstage(repoURL: self.repoURL, paths: [])
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("stage with multi-file list passes through to `git add --`")
    func stageMultiFile() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitStageRunner(runner: mock, resolveBinary: { self.binaryURL })
        try await runner.stage(repoURL: repoURL, paths: ["a.swift", "dir/b.swift"])
        let expected = ["-C", repoURL.path, "add", "--", "a.swift", "dir/b.swift"]
        #expect(mock.recordedCalls == [expected])
    }

    @Test("unstage uses `git reset HEAD --`")
    func unstageArgs() async throws {
        let mock = MockGitProcessRunner()
        let runner = GitStageRunner(runner: mock, resolveBinary: { self.binaryURL })
        try await runner.unstage(repoURL: repoURL, paths: ["foo"])
        let expected = ["-C", repoURL.path, "reset", "HEAD", "--", "foo"]
        #expect(mock.recordedCalls == [expected])
    }

    @Test("non-zero exit surfaces stderr")
    func nonZeroExit() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "add", "--", "x"]
        mock.exitCodeForArgs[args] = 128
        mock.stderrForArgs[args] = "fatal: pathspec not matched\n"
        let runner = GitStageRunner(runner: mock, resolveBinary: { self.binaryURL })
        await #expect(throws: GitCommandError.self) {
            try await runner.stage(repoURL: self.repoURL, paths: ["x"])
        }
    }
}
