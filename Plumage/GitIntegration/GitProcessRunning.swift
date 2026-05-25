import Darwin
import Foundation

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
            return "`git` nicht gefunden — Command-Line-Tools installiert?"
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

        do {
            try process.run()
        } catch {
            throw GitProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            async let stdoutData = Task.detached {
                (try? stdoutHandle.readToEnd()) ?? Data()
            }.value
            async let stderrData = Task.detached {
                (try? stderrHandle.readToEnd()) ?? Data()
            }.value
            async let exit: Int32 = Task.detached {
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            let (out, err, code) = await (stdoutData, stderrData, exit)
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

// @unchecked Sendable: stdoutForArgs is mutable but only read after the
// runner is fully configured by the test, so there is no concurrent
// write/read window in practice. Lock-free is acceptable for test doubles
// per the existing MockXcode-style precedent.
nonisolated final class MockGitProcessRunner: GitProcessRunning, @unchecked Sendable {
    var stdoutForArgs: [[String]: String] = [:]
    var exitCodeForArgs: [[String]: Int32] = [:]
    var stderrForArgs: [[String]: String] = [:]
    var recordedCalls: [[String]] = []
    var error: GitProcessRunnerError?

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> GitSpawnResult {
        recordedCalls.append(args)
        if let error { throw error }
        let stdout = stdoutForArgs[args].map { Data($0.utf8) } ?? Data()
        let stderr = stderrForArgs[args].map { Data($0.utf8) } ?? Data()
        let code = exitCodeForArgs[args] ?? 0
        return GitSpawnResult(exitCode: code, stdout: stdout, stderr: stderr)
    }
}
