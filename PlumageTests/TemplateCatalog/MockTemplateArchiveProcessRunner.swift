import Foundation
import os

@testable import Plumage

// Mutable state behind an OSAllocatedUnfairLock; @unchecked Sendable stays —
// the lock provides the actual concurrency safety.
nonisolated final class MockTemplateArchiveProcessRunner: TemplateArchiveProcessRunning,
    @unchecked Sendable
{
    private struct State: Sendable {
        var stdoutForArgs: [[String]: String] = [:]
        var exitCodeForArgs: [[String]: Int32] = [:]
        var recordedCalls: [[String]] = []
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

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> TemplateArchiveSpawnResult {
        let result: (stdout: Data, code: Int32) = lock.withLock { state in
            state.recordedCalls.append(args)
            let stdout = state.stdoutForArgs[args].map { Data($0.utf8) } ?? Data()
            let code = state.exitCodeForArgs[args] ?? 0
            return (stdout, code)
        }
        return TemplateArchiveSpawnResult(exitCode: result.code, stdout: result.stdout, stderr: Data())
    }
}
