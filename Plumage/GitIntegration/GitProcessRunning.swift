import Darwin
import Foundation
import os

nonisolated struct GitSpawnResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

nonisolated enum GitProcessRunnerError: Error, Sendable, Equatable {
    case gitNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var displayMessage: String {
        switch self {
        case .gitNotFound:
            return "`git` not found — are the Command Line Tools installed?"
        case .spawnFailed(let description):
            return "Failed to launch git: \(description)"
        case .nonZeroExit(let code, let stderr):
            let snippet = stderr.prefix(200)
            return "git exited with code \(code): \(snippet)"
        }
    }
}

nonisolated protocol GitProcessRunning: Sendable {
    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> GitSpawnResult
}

nonisolated struct ProductionGitProcessRunner: GitProcessRunning {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> GitSpawnResult {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Await exit via terminationHandler, NOT Task.detached { waitUntilExit() }.
        // waitUntilExit() spins a CFRunLoop on the calling thread to wait for the
        // child-termination mach message; called from the Swift cooperative pool
        // that wakeup races with Foundation's child-monitoring queue and is lost,
        // so the call blocks forever even after the child has exited and both
        // reads have EOF'd. terminationHandler fires on Foundation's own queue
        // with no runloop dependency. Root-caused with a standalone repro:
        // leaky form hung 2/2, this form passed 6/6 (#00057, notes.md/decisions.md).
        let termination = GitProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw GitProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
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
            if Task.isCancelled { throw CancellationError() }
            return GitSpawnResult(exitCode: code, stdout: out, stderr: err)
        } onCancel: {
            Self.cancelProcess(process)
        }
    }

    static func cancelProcess(_ process: Process) {
        // SIGTERM → 2 s grace → SIGKILL. Mirrors the pattern documented in
        // notes.md 2026-05-15 (#00019) — process.isRunning re-check closes the
        // PID-recycling race after Foundation reaps the child.
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        Task.detached { [process] in
            try? await Task.sleep(for: .seconds(Self.cancellationGraceSeconds))
            if pid > 0, process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}

// Bridges Process.terminationHandler — which Foundation may invoke on its own
// queue before OR after the awaiting continuation is installed — to a single
// continuation resume. The lock makes the early-vs-late ordering race-free.
// Replaces waitUntilExit(), which deadlocks on the Swift cooperative pool
// (#00057).
nonisolated final class GitProcessTermination: Sendable {
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

#if DEBUG
// All mutable state lives behind an OSAllocatedUnfairLock so the mock is
// safe to share across the concurrent reload() invocations in
// DiffTabModelTests.rapidReloadsCancel. @unchecked Sendable stays — the
// lock provides the actual concurrency safety.
nonisolated final class MockGitProcessRunner: GitProcessRunning, @unchecked Sendable {
    private struct State: Sendable {
        var stdoutForArgs: [[String]: String] = [:]
        var exitCodeForArgs: [[String]: Int32] = [:]
        var stderrForArgs: [[String]: String] = [:]
        var recordedCalls: [[String]] = []
        var error: GitProcessRunnerError?
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    var stdoutForArgs: [[String]: String] {
        get { lock.withLock { $0.stdoutForArgs } }
        set { lock.withLock { $0.stdoutForArgs = newValue } }
    }

    var exitCodeForArgs: [[String]: Int32] {
        get { lock.withLock { $0.exitCodeForArgs } }
        set { lock.withLock { $0.exitCodeForArgs = newValue } }
    }

    var stderrForArgs: [[String]: String] {
        get { lock.withLock { $0.stderrForArgs } }
        set { lock.withLock { $0.stderrForArgs = newValue } }
    }

    var recordedCalls: [[String]] {
        get { lock.withLock { $0.recordedCalls } }
        set { lock.withLock { $0.recordedCalls = newValue } }
    }

    var error: GitProcessRunnerError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> GitSpawnResult {
        let result: (stdout: Data, stderr: Data, code: Int32, error: GitProcessRunnerError?) =
            lock.withLock { state in
                state.recordedCalls.append(args)
                let stdout = state.stdoutForArgs[args].map { Data($0.utf8) } ?? Data()
                let stderr = state.stderrForArgs[args].map { Data($0.utf8) } ?? Data()
                let code = state.exitCodeForArgs[args] ?? 0
                return (stdout, stderr, code, state.error)
            }
        if let err = result.error { throw err }
        return GitSpawnResult(exitCode: result.code, stdout: result.stdout, stderr: result.stderr)
    }
}
#endif
