import Foundation
import Testing

@testable import Plumage

@Suite("GitRemoteURLRunner")
struct GitRemoteURLRunnerTests {
    private let repo = URL(fileURLWithPath: "/tmp/repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")

    @Test("parses https, ssh, and scp-like GitHub remotes to host + owner")
    func parsesRemoteForms() {
        let expected = GitRemoteInfo(host: "github.com", owner: "octocat")
        #expect(GitRemoteURLRunner.parse(remoteURL: "https://github.com/octocat/Hello-World.git") == expected)
        #expect(GitRemoteURLRunner.parse(remoteURL: "https://github.com/octocat/Hello-World") == expected)
        #expect(GitRemoteURLRunner.parse(remoteURL: "git@github.com:octocat/Hello-World.git") == expected)
        #expect(GitRemoteURLRunner.parse(remoteURL: "ssh://git@github.com/octocat/Hello-World.git") == expected)
        #expect(GitRemoteURLRunner.parse(remoteURL: "https://user@github.com/octocat/Hello-World.git") == expected)
    }

    @Test("normalizes the host to lowercase but keeps owner case")
    func normalizesHost() {
        let info = GitRemoteURLRunner.parse(remoteURL: "git@GitHub.com:Octocat/Repo.git")
        #expect(info?.host == "github.com")
        #expect(info?.owner == "Octocat")
    }

    @Test("non-URL, empty, and local remotes return nil")
    func rejectsNonRemotes() {
        #expect(GitRemoteURLRunner.parse(remoteURL: "") == nil)
        #expect(GitRemoteURLRunner.parse(remoteURL: "/tmp/local/repo") == nil)
        #expect(GitRemoteURLRunner.parse(remoteURL: "not a url") == nil)
    }

    @Test("originRemote runs remote get-url and parses stdout")
    func originRemoteHappyPath() async {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "remote", "get-url", "origin"]] =
            "https://github.com/octocat/Hello-World.git\n"
        let runner = GitRemoteURLRunner(runner: mock, resolveBinary: { self.fakeGit })
        #expect(await runner.originRemote(for: repo) == GitRemoteInfo(host: "github.com", owner: "octocat"))
    }

    @Test("originRemote returns nil when there is no origin")
    func originRemoteNoOrigin() async {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[["-C", repo.path, "remote", "get-url", "origin"]] = 1
        let runner = GitRemoteURLRunner(runner: mock, resolveBinary: { self.fakeGit })
        #expect(await runner.originRemote(for: repo) == nil)
    }

    @Test("originRemote returns nil when git can't be resolved")
    func originRemoteNoBinary() async {
        let runner = GitRemoteURLRunner(runner: MockGitProcessRunner(), resolveBinary: { nil })
        #expect(await runner.originRemote(for: repo) == nil)
    }

    @Test("remoteInfo resolves an arbitrary remote by name")
    func remoteInfoNonOrigin() async {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "remote", "get-url", "upstream"]] =
            "git@github.com:acme/tools.git\n"
        let runner = GitRemoteURLRunner(runner: mock, resolveBinary: { self.fakeGit })
        #expect(
            await runner.remoteInfo(for: repo, remote: "upstream")
                == GitRemoteInfo(host: "github.com", owner: "acme"))
    }

    @Test("remoteInfo rejects an option-shaped remote name without running git")
    func remoteInfoUnsafeName() async {
        let mock = MockGitProcessRunner()
        let runner = GitRemoteURLRunner(runner: mock, resolveBinary: { self.fakeGit })
        #expect(await runner.remoteInfo(for: repo, remote: "--exec=evil") == nil)
        #expect(mock.recordedCalls.isEmpty)
    }
}
