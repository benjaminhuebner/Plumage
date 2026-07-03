import Foundation
import Testing

@testable import Plumage

@Suite("GitRemoteAddRunner")
struct GitRemoteAddRunnerTests {
    private let repo = URL(fileURLWithPath: "/tmp/repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")

    private func makeRunner(_ mock: MockGitProcessRunner) -> GitRemoteAddRunner {
        GitRemoteAddRunner(runner: mock, resolveBinary: { self.fakeGit })
    }

    @Test("addRemote builds `git -C <repo> remote add <name> <url>`")
    func buildsArgs() async throws {
        let mock = MockGitProcessRunner()
        try await makeRunner(mock).addRemote(
            name: "origin", url: "https://github.com/octocat/hello.git", repoURL: repo)
        #expect(
            mock.recordedCalls == [
                ["-C", repo.path, "remote", "add", "origin", "https://github.com/octocat/hello.git"]
            ])
    }

    @Test("a leading-dash name is blocked and never reaches git")
    func unsafeNameGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitRemoteAddError.unsafeName("--upload-pack=x")) {
            try await makeRunner(mock).addRemote(
                name: "--upload-pack=x", url: "https://github.com/o/r.git", repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("a leading-dash URL is blocked and never reaches git")
    func unsafeURLGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitRemoteAddError.unsafeURL("--foo")) {
            try await makeRunner(mock).addRemote(name: "origin", url: "--foo", repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("an empty URL is rejected as unsafe")
    func emptyURLGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitRemoteAddError.unsafeURL("   ")) {
            try await makeRunner(mock).addRemote(name: "origin", url: "   ", repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("an ext:: remote-helper URL is blocked and never reaches git")
    func remoteHelperURLGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitRemoteAddError.unsafeURL("ext::sh -c 'x'")) {
            try await makeRunner(mock).addRemote(name: "origin", url: "ext::sh -c 'x'", repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("a scheme URL and an scp-like address pass the guard")
    func legitURLsPass() async throws {
        let mock = MockGitProcessRunner()
        try await makeRunner(mock).addRemote(name: "origin", url: "git@github.com:o/r.git", repoURL: repo)
        let expected = ["-C", repo.path, "remote", "add", "origin", "git@github.com:o/r.git"]
        #expect(mock.recordedCalls == [expected])
    }

    @Test("a non-zero exit (name already exists) surfaces nonZeroExit")
    func existingRemoteFails() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repo.path, "remote", "add", "origin", "https://github.com/o/r.git"]
        mock.exitCodeForArgs[args] = 3
        mock.stderrForArgs[args] = "error: remote origin already exists."
        await #expect(throws: GitRemoteAddError.self) {
            try await makeRunner(mock).addRemote(
                name: "origin", url: "https://github.com/o/r.git", repoURL: repo)
        }
    }

    @Test("a missing git binary surfaces gitNotFound")
    func missingBinary() async {
        let runner = GitRemoteAddRunner(runner: MockGitProcessRunner(), resolveBinary: { nil })
        await #expect(throws: GitRemoteAddError.gitNotFound) {
            try await runner.addRemote(name: "origin", url: "https://github.com/o/r.git", repoURL: repo)
        }
    }

    @Test("a spawn failure maps to spawnFailed")
    func spawnFailureMapped() async {
        let mock = MockGitProcessRunner()
        mock.error = .spawnFailed("boom")
        await #expect(throws: GitRemoteAddError.spawnFailed("boom")) {
            try await makeRunner(mock).addRemote(
                name: "origin", url: "https://github.com/o/r.git", repoURL: repo)
        }
    }
}
