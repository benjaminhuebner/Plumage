import Foundation
import Testing

@testable import Plumage

@Suite("GitDiffRunner")
struct GitDiffRunnerTests {
    private let fakeBinary = URL(fileURLWithPath: "/usr/bin/git")
    private let repo = URL(fileURLWithPath: "/tmp/repo")

    private func makeRunner(mock: MockGitProcessRunner) -> GitDiffRunner {
        let binary = fakeBinary
        return GitDiffRunner(runner: mock, resolveBinary: { binary })
    }

    @Test("returns diff stdout for happy path")
    func happyPath() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "main"]] = "abc123\n"
        mock.stdoutForArgs[["-C", repo.path, "diff", "main...HEAD"]] = "diff --git a/x b/x\n"
        let runner = makeRunner(mock: mock)
        let diff = try await runner.run(repoURL: repo)
        #expect(diff == "diff --git a/x b/x\n")
        #expect(mock.recordedCalls.count == 3)
    }

    @Test("throws .gitNotFound when binary cannot be resolved")
    func gitNotFound() async {
        let mock = MockGitProcessRunner()
        let runner = GitDiffRunner(runner: mock, resolveBinary: { nil })
        do {
            _ = try await runner.run(repoURL: repo)
            Issue.record("expected throw")
        } catch let error as GitDiffError {
            #expect(error == .gitNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("throws .repoNotFound when rev-parse --git-dir exits non-zero")
    func repoMissing() async {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = 128
        let runner = makeRunner(mock: mock)
        do {
            _ = try await runner.run(repoURL: repo)
            Issue.record("expected throw")
        } catch let error as GitDiffError {
            #expect(error == .repoNotFound(repo))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("throws .baseBranchMissing when rev-parse <base> exits non-zero")
    func baseMissing() async {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.exitCodeForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "main"]] = 1
        let runner = makeRunner(mock: mock)
        do {
            _ = try await runner.run(repoURL: repo)
            Issue.record("expected throw")
        } catch let error as GitDiffError {
            #expect(error == .baseBranchMissing("main"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("forwards non-zero exit code from diff to caller")
    func diffNonZero() async {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "main"]] = "abc\n"
        mock.exitCodeForArgs[["-C", repo.path, "diff", "main...HEAD"]] = 1
        mock.stderrForArgs[["-C", repo.path, "diff", "main...HEAD"]] = "fatal\n"
        let runner = makeRunner(mock: mock)
        do {
            _ = try await runner.run(repoURL: repo)
            Issue.record("expected throw")
        } catch let error as GitDiffError {
            if case .nonZeroExit(let code, let stderr) = error {
                #expect(code == 1)
                #expect(stderr.contains("fatal"))
            } else {
                Issue.record("expected .nonZeroExit, got \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("custom base argument is forwarded to the diff command")
    func customBase() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--git-dir"]] = ".git\n"
        mock.stdoutForArgs[["-C", repo.path, "rev-parse", "--verify", "--quiet", "develop"]] = "abc\n"
        mock.stdoutForArgs[["-C", repo.path, "diff", "develop...HEAD"]] = "diff content"
        let runner = makeRunner(mock: mock)
        let result = try await runner.run(repoURL: repo, base: "develop")
        #expect(result == "diff content")
    }

    @Test("smoke: diff main...HEAD against the real Plumage repo runs")
    func smokeAgainstRealRepo() async throws {
        // #filePath resolves to .../PlumageTests/GitIntegration/GitDiffRunnerTests.swift
        // The repo root is two levels up.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot =
            testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runner = GitDiffRunner(runner: ProductionGitProcessRunner())
        // Either the command succeeds (HEAD has commits past main) or it
        // throws .baseBranchMissing when the test repo has no main yet. Both
        // are valid signals that the subprocess plumbing works end-to-end.
        do {
            let diff = try await runner.run(repoURL: repoRoot)
            #expect(diff.isEmpty || diff.contains("diff --git"))
        } catch GitDiffError.baseBranchMissing {
            // Acceptable on shallow worktrees / fresh clones.
        }
    }
}
