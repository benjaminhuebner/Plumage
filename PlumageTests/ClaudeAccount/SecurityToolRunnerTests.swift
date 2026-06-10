import Foundation
import Testing

@testable import Plumage

@Suite("SecurityToolRunner")
struct SecurityToolRunnerTests {
    @Test("captures stdout and zero exit code")
    func capturesStdout() async throws {
        let runner = ProductionSecurityToolRunner(
            binaryURL: URL(fileURLWithPath: "/bin/echo"))
        let result = try await runner.run(args: ["hello"])
        #expect(result.exitCode == 0)
        #expect(String(data: result.stdout, encoding: .utf8) == "hello\n")
    }

    @Test("surfaces nonzero exit code")
    func surfacesNonzeroExit() async throws {
        let runner = ProductionSecurityToolRunner(
            binaryURL: URL(fileURLWithPath: "/usr/bin/false"))
        let result = try await runner.run(args: [])
        #expect(result.exitCode != 0)
    }

    @Test("times out instead of hanging on a stuck process")
    func timesOut() async throws {
        let runner = ProductionSecurityToolRunner(
            binaryURL: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.2)
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: SecurityToolError.timedOut) {
            _ = try await runner.run(args: ["5"])
        }
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(3))
    }

    @Test("missing binary surfaces spawnFailed")
    func spawnFailure() async {
        let runner = ProductionSecurityToolRunner(
            binaryURL: URL(fileURLWithPath: "/nonexistent/binary"))
        do {
            _ = try await runner.run(args: [])
            Issue.record("expected spawnFailed")
        } catch let error as SecurityToolError {
            guard case .spawnFailed = error else {
                Issue.record("expected spawnFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("expected SecurityToolError, got \(error)")
        }
    }

    @Test("mock returns configured result and records calls")
    func mockReturnsConfigured() async throws {
        let mock = MockSecurityToolRunner()
        mock.stdoutForArgs = [["find-generic-password", "-w"]: "secret"]
        mock.exitCodeForArgs = [["find-generic-password", "-w"]: 0]
        let result = try await mock.run(args: ["find-generic-password", "-w"])
        #expect(String(data: result.stdout, encoding: .utf8) == "secret")
        #expect(result.exitCode == 0)
        #expect(mock.recordedCalls == [["find-generic-password", "-w"]])
    }

    @Test("mock throws configured error")
    func mockThrowsError() async {
        let mock = MockSecurityToolRunner()
        mock.error = .timedOut
        await #expect(throws: SecurityToolError.timedOut) {
            _ = try await mock.run(args: [])
        }
    }
}
