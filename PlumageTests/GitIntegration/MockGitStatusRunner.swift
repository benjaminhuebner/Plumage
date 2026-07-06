import Foundation
import os

@testable import Plumage

// Test stub for higher-level features (GitCommitModel, ProjectStatusBar).
// @unchecked Sendable: all mutable state lives inside the
// OSAllocatedUnfairLock<State>; every access goes through withLock.
nonisolated final class MockGitStatusRunner: GitStatusRunning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State: Sendable {
        var outputs: [URL: [GitFileStatus]] = [:]
        var error: GitCommandError?
    }

    var outputs: [URL: [GitFileStatus]] {
        get { lock.withLock { $0.outputs } }
        set { lock.withLock { $0.outputs = newValue } }
    }

    var error: GitCommandError? {
        get { lock.withLock { $0.error } }
        set { lock.withLock { $0.error = newValue } }
    }

    func run(repoURL: URL) async throws -> [GitFileStatus] {
        let result: (error: GitCommandError?, output: [GitFileStatus]) = lock.withLock { state in
            (state.error, state.outputs[repoURL] ?? [])
        }
        if let error = result.error { throw error }
        return result.output
    }
}
