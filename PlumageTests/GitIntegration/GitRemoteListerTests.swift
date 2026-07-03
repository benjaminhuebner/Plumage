import Foundation
import Testing

@testable import Plumage

@Suite("GitRemoteLister")
struct GitRemoteListerTests {
    private let repo = URL(fileURLWithPath: "/tmp/repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")

    @Test("parse splits, trims, and drops empty lines")
    func parseOutput() {
        #expect(GitRemoteLister.parse(output: "origin\nupstream\n") == ["origin", "upstream"])
        #expect(GitRemoteLister.parse(output: "  origin  \n\nfork\n") == ["origin", "fork"])
        #expect(GitRemoteLister.parse(output: "").isEmpty)
        #expect(GitRemoteLister.parse(output: "\n\n").isEmpty)
    }

    @Test("remotes runs `git remote` and returns the parsed names")
    func remotesHappyPath() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "remote"]] = "origin\nupstream\n"
        let lister = GitRemoteLister(runner: mock, resolveBinary: { self.fakeGit })
        #expect(try await lister.remotes(repoURL: repo) == ["origin", "upstream"])
    }

    @Test("a repo with no remotes returns an empty list, not an error")
    func remotesEmpty() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "remote"]] = ""
        let lister = GitRemoteLister(runner: mock, resolveBinary: { self.fakeGit })
        #expect(try await lister.remotes(repoURL: repo).isEmpty)
    }

    @Test("a non-zero git exit surfaces listFailed")
    func remotesFailure() async {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[["-C", repo.path, "remote"]] = 128
        mock.stderrForArgs[["-C", repo.path, "remote"]] = "fatal: not a git repository"
        let lister = GitRemoteLister(runner: mock, resolveBinary: { self.fakeGit })
        await #expect(throws: GitRemoteListError.self) {
            _ = try await lister.remotes(repoURL: repo)
        }
    }

    @Test("a missing git binary surfaces gitNotFound")
    func remotesNoBinary() async {
        let lister = GitRemoteLister(runner: MockGitProcessRunner(), resolveBinary: { nil })
        await #expect(throws: GitRemoteListError.gitNotFound) {
            _ = try await lister.remotes(repoURL: repo)
        }
    }
}
