import Foundation
import os

@testable import Plumage

// Replays a scripted sequence of lines and a chosen exit code, in order.
// Used by GitSyncRunner tests to drive auth-prompt-detection and
// set-upstream-retry scenarios.
nonisolated final class MockGitProcessStreamer: GitProcessStreaming, @unchecked Sendable {
    private struct Script: Sendable {
        let lines: [GitStreamLine]
        let exitCode: Int32
    }

    private struct State: Sendable {
        var scripts: [[String]: [Script]] = [:]
        var error: GitProcessRunnerError?
        var calls: [[String]] = []
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    var error: GitProcessRunnerError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    var calls: [[String]] {
        lock.withLock { $0.calls }
    }

    // Queue a script for `args`. Each call to stream() consumes the first
    // queued script for the matching args; this lets a test pre-program
    // "first push fails with no-upstream, retry succeeds" by queuing two.
    func enqueue(args: [String], lines: [GitStreamLine], exitCode: Int32) {
        lock.withLock { state in
            var existing = state.scripts[args] ?? []
            existing.append(Script(lines: lines, exitCode: exitCode))
            state.scripts[args] = existing
        }
    }

    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?
    ) async throws -> (AsyncStream<GitStreamLine>, () async -> GitStreamOutcome) {
        let pulled: (script: Script?, error: GitProcessRunnerError?) = lock.withLock { state in
            state.calls.append(args)
            if let err = state.error { return (nil, err) }
            var queue = state.scripts[args] ?? []
            let head = queue.isEmpty ? nil : queue.removeFirst()
            state.scripts[args] = queue
            return (head, nil)
        }
        if let err = pulled.error { throw err }
        let script = pulled.script ?? Script(lines: [], exitCode: 0)

        let (stream, cont) = AsyncStream<GitStreamLine>.makeStream()
        for line in script.lines { cont.yield(line) }
        cont.finish()

        let outcome: @Sendable () async -> GitStreamOutcome = {
            GitStreamOutcome(exitCode: script.exitCode)
        }
        return (stream, outcome)
    }
}
