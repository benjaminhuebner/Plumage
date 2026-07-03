import Foundation
import os

@testable import Plumage

// All mutable state lives behind an OSAllocatedUnfairLock so the mock is safe
// to share across concurrent reload() invocations (DiffTabModelTests).
// @unchecked Sendable: the lock provides the actual concurrency safety.
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
