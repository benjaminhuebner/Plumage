import Darwin
import Foundation
import os

nonisolated struct TemplateArchiveSpawnResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

nonisolated enum TemplateArchiveProcessRunnerError: Error, Sendable, Equatable {
    case spawnFailed(String)

    var displayMessage: String {
        switch self {
        case .spawnFailed(let description):
            return "Failed to launch archive tool: \(description)"
        }
    }
}

nonisolated protocol TemplateArchiveProcessRunning: Sendable {
    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> TemplateArchiveSpawnResult
}

nonisolated struct ProductionTemplateArchiveProcessRunner: TemplateArchiveProcessRunning {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> TemplateArchiveSpawnResult {
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

        // Await exit via terminationHandler, NOT waitUntilExit() — the latter
        // races Foundation's child-monitoring queue from the Swift cooperative
        // pool and can block forever (root-caused for GitProcessRunning).
        let termination = TemplateArchiveProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw TemplateArchiveProcessRunnerError.spawnFailed(error.localizedDescription)
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
            return TemplateArchiveSpawnResult(exitCode: code, stdout: out, stderr: err)
        } onCancel: {
            Self.cancelProcess(process)
        }
    }

    static func cancelProcess(_ process: Process) {
        // SIGTERM → 2 s grace → SIGKILL — the process.isRunning re-check
        // closes the PID-recycling race after Foundation reaps the child.
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
nonisolated final class TemplateArchiveProcessTermination: Sendable {
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
#endif
