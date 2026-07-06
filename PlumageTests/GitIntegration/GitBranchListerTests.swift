import Foundation
import Testing

@testable import Plumage

struct GitBranchListerTests {
    @Test("for-each-ref output parses one branch per line")
    func parseOutput() {
        let output = """
            main
            issue/00042-feature
            release/1.0

            """

        let branches = GitBranchLister.parse(output: output)

        #expect(branches == ["main", "issue/00042-feature", "release/1.0"])
    }

    @Test("empty output yields no branches")
    func parseEmpty() {
        #expect(GitBranchLister.parse(output: "").isEmpty)
    }

    @Test("successful run returns parsed branches")
    func listBranches() async throws {
        let mock = MockGitProcessRunner()
        let args = ["-C", "/tmp", "for-each-ref", "--format=%(refname:short)", "refs/heads/"]
        mock.stdoutForArgs = [args: "main\nissue/00042-feature\n"]
        let lister = GitBranchLister(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        let branches = try await lister.branches(repoURL: URL(filePath: "/tmp"))

        #expect(branches == ["main", "issue/00042-feature"])
    }

    @Test("non-zero exit throws nonZeroExit with stderr")
    func nonZeroExitThrows() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", "/tmp", "for-each-ref", "--format=%(refname:short)", "refs/heads/"]
        mock.exitCodeForArgs = [args: 128]
        mock.stderrForArgs = [args: "fatal: not a git repository"]
        let lister = GitBranchLister(
            runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })

        await #expect(
            throws: GitCommandError.nonZeroExit(
                command: "git for-each-ref", code: 128, stderr: "fatal: not a git repository")
        ) {
            _ = try await lister.branches(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test("missing git binary throws gitNotFound")
    func missingBinaryThrows() async {
        let lister = GitBranchLister(runner: MockGitProcessRunner(), resolveBinary: { nil })

        await #expect(throws: GitCommandError.gitNotFound) {
            _ = try await lister.branches(repoURL: URL(filePath: "/tmp"))
        }
    }

    @Test(
        "real repo lists its local branches",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func realBranchEnumeration() async throws {
        let repo = try await TmpGitRepo.make()
        let binary = try #require(ToolchainLocator.git())
        let runner = ProductionGitProcessRunner()
        let create = try await runner.run(
            binaryURL: binary,
            args: ["branch", "feature/extra"],
            cwd: repo.tmpDir
        )
        try #require(create.exitCode == 0, "branch create failed")

        let branches = try await GitBranchLister().branches(repoURL: repo.tmpDir)

        #expect(branches.contains("feature/extra"))
        #expect(branches.contains(repo.mainBranch))
    }
}
