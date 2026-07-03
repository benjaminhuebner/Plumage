import Darwin
import Foundation
import os

nonisolated struct SecurityToolResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: Data
}

nonisolated enum SecurityToolError: Error, Sendable, Equatable {
    case spawnFailed(String)
    case timedOut
}

nonisolated protocol SecurityToolRunning: Sendable {
    func run(args: [String]) async throws -> SecurityToolResult
}

nonisolated struct ProductionSecurityToolRunner: SecurityToolRunning {
    // `security` can hang on some macOS systems — a stuck read must degrade
    // to a transient error, never block the app.
    static let defaultTimeout: TimeInterval = 3.0
    static let killGraceSeconds: TimeInterval = 1.0

    // Whatever runs at binaryURL inherits the app's Keychain access — it must
    // stay a trusted system path; the parameter exists for test injection only.
    let binaryURL: URL
    let timeout: TimeInterval

    init(
        binaryURL: URL = URL(fileURLWithPath: "/usr/bin/security"),
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.binaryURL = binaryURL
        self.timeout = timeout
    }

    func run(args: [String]) async throws -> SecurityToolResult {
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

        // waitUntilExit() spins a CFRunLoop on the cooperative pool and can
        // miss the child-exit wakeup, blocking forever (same fix as git runner).
        let termination = SecurityToolTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw SecurityToolError.spawnFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            async let stdoutData = Task.detached {
                (try? stdoutHandle.readToEnd()) ?? Data()
            }.value
            // stderr is drained but not surfaced — an unread pipe that fills
            // its buffer would block the child on write() and deadlock the run.
            async let stderrData = Task.detached {
                (try? stderrHandle.readToEnd()) ?? Data()
            }.value

            let timeoutTask = Task.detached { [timeout] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                if termination.expire() {
                    Self.killProcess(process)
                }
            }
            let code = await withCheckedContinuation {
                (continuation: CheckedContinuation<Int32?, Never>) in
                termination.attach(continuation)
            }
            timeoutTask.cancel()
            guard let code else {
                // The kill EOFs the pipes; await so no reader outlives the call.
                _ = await (stdoutData, stderrData)
                throw SecurityToolError.timedOut
            }
            let (out, _) = await (stdoutData, stderrData)
            if Task.isCancelled { throw CancellationError() }
            return SecurityToolResult(exitCode: code, stdout: out)
        } onCancel: {
            Self.killProcess(process)
        }
    }

    static func killProcess(_ process: Process) {
        // SIGTERM → grace → SIGKILL; the isRunning re-check closes the
        // PID-recycling race after Foundation reaps the child.
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        Task.detached { [process] in
            try? await Task.sleep(for: .seconds(Self.killGraceSeconds))
            if pid > 0, process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}

// terminationHandler may fire before or after the waiter attaches, and may
// race expire(); the lock makes every ordering resume exactly once.
nonisolated final class SecurityToolTermination: Sendable {
    private struct State {
        var status: Int32?
        var expired = false
        var continuation: CheckedContinuation<Int32?, Never>?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    func complete(_ status: Int32) {
        state.withLock { box in
            guard !box.expired else { return }
            if let continuation = box.continuation {
                box.continuation = nil
                continuation.resume(returning: status)
            } else {
                box.status = status
            }
        }
    }

    func expire() -> Bool {
        state.withLock { box in
            guard box.status == nil, !box.expired else { return false }
            box.expired = true
            if let continuation = box.continuation {
                box.continuation = nil
                continuation.resume(returning: nil)
            }
            return true
        }
    }

    func attach(_ continuation: CheckedContinuation<Int32?, Never>) {
        state.withLock { box in
            if let status = box.status {
                continuation.resume(returning: status)
            } else if box.expired {
                continuation.resume(returning: nil)
            } else {
                box.continuation = continuation
            }
        }
    }
}

#if DEBUG
// @unchecked Sendable: all mutable state behind an OSAllocatedUnfairLock,
// same rationale as MockGitProcessRunner.
nonisolated final class MockSecurityToolRunner: SecurityToolRunning, @unchecked Sendable {
    private struct State: Sendable {
        var stdoutForArgs: [[String]: String] = [:]
        var exitCodeForArgs: [[String]: Int32] = [:]
        var recordedCalls: [[String]] = []
        var error: SecurityToolError?
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

    var recordedCalls: [[String]] {
        get { lock.withLock { $0.recordedCalls } }
        set { lock.withLock { $0.recordedCalls = newValue } }
    }

    var error: SecurityToolError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    func run(args: [String]) async throws -> SecurityToolResult {
        let result: (stdout: Data, code: Int32, error: SecurityToolError?) =
            lock.withLock { state in
                state.recordedCalls.append(args)
                let stdout = state.stdoutForArgs[args].map { Data($0.utf8) } ?? Data()
                let code = state.exitCodeForArgs[args] ?? 0
                return (stdout, code, state.error)
            }
        if let err = result.error { throw err }
        return SecurityToolResult(exitCode: result.code, stdout: result.stdout)
    }
}
#endif
