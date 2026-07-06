import Foundation
import Testing

@testable import Plumage

struct GitTagListerTests {
    @Test("for-each-ref output parses one tag per line")
    func parseOutput() {
        let output = """
            v2.0.0
            v1.1.0
            v1.0.0

            """

        let tags = GitTagLister.parse(output: output)

        #expect(tags == ["v2.0.0", "v1.1.0", "v1.0.0"])
    }

    @Test("empty output yields no tags")
    func parseEmpty() {
        #expect(GitTagLister.parse(output: "").isEmpty)
    }

    @Test("successful run returns parsed tags, newest first")
    func listTags() async throws {
        let mock = MockGitProcessRunner()
        let args = [
            "-C", "/tmp", "for-each-ref", "--sort=-creatordate",
            "--format=%(refname:short)", "refs/tags/",
        ]
        mock.stdoutForArgs = [args: "v2.0.0\nv1.0.0\n"]
        let lister = GitTagLister(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        let tags = try await lister.tags(repoURL: URL(filePath: "/tmp"))

        #expect(tags == ["v2.0.0", "v1.0.0"])
    }

    @Test("non-zero exit throws nonZeroExit with stderr")
    func nonZeroExitThrows() async {
        let mock = MockGitProcessRunner()
        let args = [
            "-C", "/tmp", "for-each-ref", "--sort=-creatordate",
            "--format=%(refname:short)", "refs/tags/",
        ]
        mock.exitCodeForArgs = [args: 128]
        mock.stderrForArgs = [args: "fatal: not a git repository"]
        let lister = GitTagLister(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        await #expect(
            throws: GitCommandError.nonZeroExit(
                command: "git for-each-ref", code: 128, stderr: "fatal: not a git repository")
        ) {
            _ = try await lister.tags(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test("missing git binary throws gitNotFound")
    func missingBinaryThrows() async {
        let lister = GitTagLister(runner: MockGitProcessRunner(), resolveBinary: { nil })

        await #expect(throws: GitCommandError.gitNotFound) {
            _ = try await lister.tags(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test(
        "real repo lists its tags",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func realTagEnumeration() async throws {
        let repo = try await TmpGitRepo.make()
        let creator = GitTagCreateRunner()
        try await creator.createTag(name: "v1.0.0", message: "release", repoURL: repo.tmpDir)
        try await creator.createTag(name: "v0.9.0", message: nil, repoURL: repo.tmpDir)

        let tags = try await GitTagLister().tags(repoURL: repo.tmpDir)

        #expect(tags.contains("v1.0.0"))
        #expect(tags.contains("v0.9.0"))
    }
}
