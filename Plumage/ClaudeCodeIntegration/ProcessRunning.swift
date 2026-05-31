import Darwin
import Foundation
import os

nonisolated protocol ProcessRunning: Sendable {
    func detectVersion() async throws -> VersionCheck
    func spawnSession(args: [String]) async throws -> SpawnResult
}

nonisolated struct ProductionProcessRunner: ProcessRunning {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func detectVersion() async throws -> VersionCheck {
        let binary = try Self.locateBinary()
        let result = try await Self.spawnAt(binaryURL: binary, args: ["--version"])
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        let stdoutString = String(decoding: result.stdout, as: UTF8.self)
        guard let version = SemanticVersion.parse(stdoutString) else {
            throw ProcessRunnerError.parseError(stdoutString)
        }
        return VersionCheck(
            version: version,
            binaryURL: binary,
            inSupportedRange: SupportedClaudeVersion.inSupportedRange(version)
        )
    }

    func spawnSession(args: [String]) async throws -> SpawnResult {
        let binary = try Self.locateBinary()
        return try await Self.spawnAt(binaryURL: binary, args: args)
    }

    // MARK: - Binary discovery

    static func locateBinary() throws(ProcessRunnerError) -> URL {
        if let viaPath = scanPATH() {
            return viaPath
        }
        for candidate in SupportedClaudeVersion.knownInstallURLs {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw .binaryNotFound
    }

    // Replaces the previous `/usr/bin/env which claude` subprocess: spawning
    // `env` blocks the caller on `waitUntilExit()` and shows up on MainActor
    // hot paths (ProjectWindow.init, ClaudeSession.rebuilt). Pure PATH walk
    // is in-process, allocation-only, and behaves identically — `which` itself
    // does the same loop on a POSIX shell.
    private static func scanPATH() -> URL? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"], !pathEnv.isEmpty else {
            return nil
        }
        let manager = FileManager.default
        for entry in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(entry))
                .appendingPathComponent("claude")
            if manager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Spawning

    // Internal access so integration tests can drive the spawn machinery with
    // /bin/echo and /bin/sleep without going through locateBinary().
    static func spawnAt(binaryURL: URL, args: [String]) async throws -> SpawnResult {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Await exit via terminationHandler, NOT Task.detached { waitUntilExit() }.
        // waitUntilExit() spins a CFRunLoop on the calling thread; on the Swift
        // cooperative pool that child-termination wakeup races with Foundation's
        // child-monitoring queue and is lost, blocking forever. terminationHandler
        // fires on Foundation's own queue, no runloop, no thread affinity.
        // Same fix as ProductionGitProcessRunner (#00057); applied here per #00058.
        let termination = ClaudeProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw ProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            // Drain stdout/stderr in parallel with the exit-await to avoid pipe-buffer deadlock.
            async let stdoutData = Task.detached {
                (try? stdoutHandle.readToEnd()) ?? Data()
            }.value
            async let stderrData = Task.detached {
                (try? stderrHandle.readToEnd()) ?? Data()
            }.value
            let code = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                termination.attach(continuation)
            }
            let (out, err) = await (stdoutData, stderrData)
            if Task.isCancelled {
                throw CancellationError()
            }
            return SpawnResult(exitCode: code, stdout: out, stderr: err)
        } onCancel: {
            // SIGTERM via Foundation, escalating to SIGKILL after grace period.
            if process.isRunning {
                process.terminate()
            }
            let pid = process.processIdentifier
            Task.detached { [process] in
                try? await Task.sleep(for: .seconds(Self.cancellationGraceSeconds))
                // Re-check isRunning to avoid SIGKILL on a recycled PID once
                // waitUntilExit has reaped the child after the SIGTERM landed.
                if pid > 0, process.isRunning {
                    _ = Darwin.kill(pid, SIGKILL)
                }
            }
        }
    }
}

// Bridges Process.terminationHandler — which Foundation may invoke on its own
// queue before OR after the awaiting continuation is installed — to a single
// continuation resume. The lock makes the early-vs-late ordering race-free.
// Replaces waitUntilExit(), which deadlocks on the Swift cooperative pool
// (#00057 root cause, #00058 applies the fix to the Claude runner). Per-domain
// copy of GitProcessTermination — decisions.md 2026-05-25 #00042 keeps the
// subprocess runners duplicated per domain rather than extracting a shared box.
nonisolated final class ClaudeProcessTermination: Sendable {
    private struct State {
        var status: Int32?
        var continuation: CheckedContinuation<Int32, Never>?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    func complete(_ status: Int32) {
        state.withLock { box in
            if let continuation = box.continuation {
                box.continuation = nil
                continuation.resume(returning: status)
            } else {
                box.status = status
            }
        }
    }

    func attach(_ continuation: CheckedContinuation<Int32, Never>) {
        state.withLock { box in
            if let status = box.status {
                continuation.resume(returning: status)
            } else {
                box.continuation = continuation
            }
        }
    }
}
