import Foundation
import Testing

@testable import Plumage

@Suite("GitWorkingDiffRunner")
struct GitWorkingDiffRunnerTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let binaryURL = URL(filePath: "/usr/bin/git")

    @Test("gitNotFound short-circuits before any subprocess call")
    func gitNotFoundShortCircuits() async {
        let mock = MockGitProcessRunner()
        let runner = GitWorkingDiffRunner(runner: mock, resolveBinary: { nil })
        await #expect(throws: GitWorkingDiffError.gitNotFound) {
            _ = try await runner.diffWorking(repoURL: self.repoURL, path: "foo.swift")
        }
        #expect(mock.recordedCalls.isEmpty)
    }

    @Test("diffWorking calls `git diff -- <path>` and returns stdout")
    func diffWorkingArgs() async throws {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "diff", "--", "Plumage/Foo.swift"]
        mock.stdoutForArgs[args] = "diff --git a/Plumage/Foo.swift b/Plumage/Foo.swift\n@@ -1,1 +1,1 @@\n-old\n+new\n"
        let runner = GitWorkingDiffRunner(runner: mock, resolveBinary: { self.binaryURL })

        let diff = try await runner.diffWorking(repoURL: repoURL, path: "Plumage/Foo.swift")
        #expect(diff.contains("+new"))
        #expect(mock.recordedCalls.count == 1)
        #expect(mock.recordedCalls.first == args)
    }

    @Test("diffStaged calls `git diff --cached -- <path>`")
    func diffStagedArgs() async throws {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "diff", "--cached", "--", "Plumage/Bar.swift"]
        mock.stdoutForArgs[args] = "staged diff\n"
        let runner = GitWorkingDiffRunner(runner: mock, resolveBinary: { self.binaryURL })

        let diff = try await runner.diffStaged(repoURL: repoURL, path: "Plumage/Bar.swift")
        #expect(diff == "staged diff\n")
    }

    @Test("non-zero exit propagates stderr as typed error")
    func nonZeroExit() async {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "diff", "--", "nope"]
        mock.exitCodeForArgs[args] = 128
        mock.stderrForArgs[args] = "fatal: bad path\n"
        let runner = GitWorkingDiffRunner(runner: mock, resolveBinary: { self.binaryURL })

        await #expect(throws: GitWorkingDiffError.self) {
            _ = try await runner.diffWorking(repoURL: self.repoURL, path: "nope")
        }
    }
}
