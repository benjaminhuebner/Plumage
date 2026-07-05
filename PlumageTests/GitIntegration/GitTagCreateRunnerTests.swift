import Foundation
import Testing

@testable import Plumage

@Suite("GitTagCreateRunner")
struct GitTagCreateRunnerTests {
    private let repo = URL(fileURLWithPath: "/tmp/repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")

    private func makeRunner(_ mock: MockGitProcessRunner) -> GitTagCreateRunner {
        GitTagCreateRunner(runner: mock, resolveBinary: { self.fakeGit })
    }

    @Test("a nil message builds a lightweight `git -C <repo> tag <name>`")
    func lightweightNilMessage() async throws {
        let mock = MockGitProcessRunner()
        try await makeRunner(mock).createTag(name: "v1.0.0", message: nil, repoURL: repo)
        #expect(mock.recordedCalls == [["-C", repo.path, "tag", "v1.0.0"]])
    }

    @Test("an empty and a whitespace-only message both stay lightweight")
    func lightweightBlankMessage() async throws {
        let mockEmpty = MockGitProcessRunner()
        try await makeRunner(mockEmpty).createTag(name: "v1.0.0", message: "", repoURL: repo)
        #expect(mockEmpty.recordedCalls == [["-C", repo.path, "tag", "v1.0.0"]])

        let mockBlank = MockGitProcessRunner()
        try await makeRunner(mockBlank).createTag(name: "v1.0.0", message: "   ", repoURL: repo)
        #expect(mockBlank.recordedCalls == [["-C", repo.path, "tag", "v1.0.0"]])
    }

    @Test("a non-empty message builds an annotated `tag -a <name> -m <message>`")
    func annotatedMessage() async throws {
        let mock = MockGitProcessRunner()
        try await makeRunner(mock).createTag(name: "v1.0.0", message: "First release", repoURL: repo)
        #expect(mock.recordedCalls == [["-C", repo.path, "tag", "-a", "v1.0.0", "-m", "First release"]])
    }

    @Test("an annotated message is trimmed before it reaches git")
    func annotatedMessageTrimmed() async throws {
        let mock = MockGitProcessRunner()
        try await makeRunner(mock).createTag(name: "v1.0.0", message: "  hello  ", repoURL: repo)
        #expect(mock.recordedCalls == [["-C", repo.path, "tag", "-a", "v1.0.0", "-m", "hello"]])
    }

    @Test("a name with a space is blocked and never reaches git")
    func unsafeNameSpaceGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitTagCreateError.invalidName("bad name")) {
            try await makeRunner(mock).createTag(name: "bad name", message: nil, repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("a leading-dash name is blocked and never reaches git")
    func unsafeNameDashGuard() async {
        let mock = MockGitProcessRunner()
        await #expect(throws: GitTagCreateError.invalidName("-x")) {
            try await makeRunner(mock).createTag(name: "-x", message: "m", repoURL: repo)
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("a non-zero exit (tag already exists) surfaces nonZeroExit")
    func existingTagFails() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repo.path, "tag", "v1.0.0"]
        mock.exitCodeForArgs[args] = 128
        mock.stderrForArgs[args] = "fatal: tag 'v1.0.0' already exists"
        await #expect(throws: GitTagCreateError.self) {
            try await makeRunner(mock).createTag(name: "v1.0.0", message: nil, repoURL: repo)
        }
    }

    @Test("a missing git binary surfaces gitNotFound")
    func missingBinary() async {
        let runner = GitTagCreateRunner(runner: MockGitProcessRunner(), resolveBinary: { nil })
        await #expect(throws: GitTagCreateError.gitNotFound) {
            try await runner.createTag(name: "v1.0.0", message: nil, repoURL: repo)
        }
    }

    @Test("a spawn failure maps to spawnFailed")
    func spawnFailureMapped() async {
        let mock = MockGitProcessRunner()
        mock.error = .spawnFailed("boom")
        await #expect(throws: GitTagCreateError.spawnFailed("boom")) {
            try await makeRunner(mock).createTag(name: "v1.0.0", message: nil, repoURL: repo)
        }
    }

    @Test(
        "real repo creates an annotated and a lightweight tag on HEAD",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func realTagCreation() async throws {
        let repo = try await TmpGitRepo.make()
        let binary = try #require(ToolchainLocator.git())
        let git = ProductionGitProcessRunner()
        let runner = GitTagCreateRunner()

        try await runner.createTag(name: "v1.0.0", message: "First release", repoURL: repo.tmpDir)
        try await runner.createTag(name: "v2.0.0", message: nil, repoURL: repo.tmpDir)

        let annotated = try await git.run(
            binaryURL: binary, args: ["-C", repo.tmpDir.path, "cat-file", "-t", "v1.0.0"], cwd: nil)
        #expect(
            String(decoding: annotated.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "tag")
        let lightweight = try await git.run(
            binaryURL: binary, args: ["-C", repo.tmpDir.path, "cat-file", "-t", "v2.0.0"], cwd: nil)
        #expect(
            String(decoding: lightweight.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "commit")

        let head = try await repo.headSha(branch: "HEAD")
        for tag in ["v1.0.0", "v2.0.0"] {
            let resolved = try await git.run(
                binaryURL: binary, args: ["-C", repo.tmpDir.path, "rev-list", "-n", "1", tag], cwd: nil)
            #expect(
                String(decoding: resolved.stdout, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines) == head)
        }
    }

    @Test(
        "real repo rejects a duplicate tag with a non-zero exit",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func realDuplicateTagFails() async throws {
        let repo = try await TmpGitRepo.make()
        let runner = GitTagCreateRunner()
        try await runner.createTag(name: "v1.0.0", message: nil, repoURL: repo.tmpDir)
        await #expect(throws: GitTagCreateError.self) {
            try await runner.createTag(name: "v1.0.0", message: nil, repoURL: repo.tmpDir)
        }
    }
}
