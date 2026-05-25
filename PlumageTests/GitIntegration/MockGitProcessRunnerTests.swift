import Foundation
import Testing

@testable import Plumage

@Suite("MockGitProcessRunner")
struct MockGitProcessRunnerTests {
    @Test("records invocation args and returns configured stdout")
    func recordsAndReturns() async throws {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["diff", "main...HEAD"]] = "diff --git a/file b/file\n"
        let result = try await mock.run(
            binaryURL: URL(fileURLWithPath: "/usr/bin/git"),
            args: ["diff", "main...HEAD"],
            cwd: nil
        )
        #expect(mock.recordedCalls == [["diff", "main...HEAD"]])
        #expect(String(decoding: result.stdout, as: UTF8.self) == "diff --git a/file b/file\n")
        #expect(result.exitCode == 0)
    }

    @Test("defaults to empty stdout and exit 0 for unmapped args")
    func unmappedDefaults() async throws {
        let mock = MockGitProcessRunner()
        let result = try await mock.run(
            binaryURL: URL(fileURLWithPath: "/usr/bin/git"),
            args: ["status"],
            cwd: nil
        )
        #expect(result.stdout.isEmpty)
        #expect(result.exitCode == 0)
    }

    @Test("throws configured error eagerly")
    func throwsConfiguredError() async {
        let mock = MockGitProcessRunner()
        mock.error = .gitNotFound
        do {
            _ = try await mock.run(
                binaryURL: URL(fileURLWithPath: "/usr/bin/git"),
                args: ["diff"],
                cwd: nil
            )
            Issue.record("expected throw")
        } catch let error as GitProcessRunnerError {
            #expect(error == .gitNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("returns configured non-zero exit code and stderr")
    func nonZeroExit() async throws {
        let mock = MockGitProcessRunner()
        mock.exitCodeForArgs[["rev-parse", "main"]] = 128
        mock.stderrForArgs[["rev-parse", "main"]] = "fatal: bad revision\n"
        let result = try await mock.run(
            binaryURL: URL(fileURLWithPath: "/usr/bin/git"),
            args: ["rev-parse", "main"],
            cwd: nil
        )
        #expect(result.exitCode == 128)
        #expect(String(decoding: result.stderr, as: UTF8.self) == "fatal: bad revision\n")
    }
}
