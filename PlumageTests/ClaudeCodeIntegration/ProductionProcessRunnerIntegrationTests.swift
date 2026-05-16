import Foundation
import Testing

@testable import Plumage

@Suite("ProductionProcessRunner integration")
struct ProductionProcessRunnerIntegrationTests {
    @Test("echoed version string parses through the detect pipeline")
    func happyDetect() async throws {
        // Drive only the spawn machinery against /bin/echo — keep locateBinary
        // out of the loop because it would resolve the real `claude` binary.
        let echoURL = URL(fileURLWithPath: "/bin/echo")
        let result = try await ProductionProcessRunner.spawnAt(
            binaryURL: echoURL, args: ["1.2.3"])
        #expect(result.exitCode == 0)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        #expect(stdout.contains("1.2.3"))
        let parsed = SemanticVersion.parse(stdout)
        #expect(parsed == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("echoed stdout reaches the SpawnResult intact")
    func happySpawn() async throws {
        let echoURL = URL(fileURLWithPath: "/bin/echo")
        let result = try await ProductionProcessRunner.spawnAt(
            binaryURL: echoURL, args: ["hello"])
        #expect(result.exitCode == 0)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        #expect(stdout == "hello\n")
        #expect(result.stderr.isEmpty)
    }

    @Test("spawnAt surfaces a non-zero exit code without throwing")
    func spawnAtNonZeroExit() async throws {
        // /usr/bin/false exits 1, /usr/bin/true exits 0 — POSIX.
        // spawnAt returns the raw SpawnResult; the .nonZeroExit error mapping
        // lives one level up in detectVersion (covered by StatusIndicatorModel tests).
        let falseURL = URL(fileURLWithPath: "/usr/bin/false")
        let result = try await ProductionProcessRunner.spawnAt(
            binaryURL: falseURL, args: [])
        #expect(result.exitCode == 1)
    }

    @Test("cancellation aborts a long-running sleep")
    func cancellation() async throws {
        let sleepURL = URL(fileURLWithPath: "/bin/sleep")
        let started = Date()
        let task = Task {
            try await ProductionProcessRunner.spawnAt(binaryURL: sleepURL, args: ["60"])
        }
        // Let the child boot, then cancel.
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected the cancelled spawn to throw or return")
        } catch is CancellationError {
            // Expected.
        } catch {
            // Other paths (e.g., signal-killed) are acceptable. We just don't
            // want the call to hang the full 60 seconds.
        }
        let elapsed = Date().timeIntervalSince(started)
        // Generous bound: the SIGTERM-then-SIGKILL grace window plus jitter.
        #expect(elapsed < 5.0, "cancellation took \(elapsed) seconds")
    }
}
