import Darwin
import Foundation
import os

nonisolated struct XcodeSpawnResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

nonisolated enum XcodeProcessRunnerError: Error, Sendable, Equatable {
    case toolchainNotFound
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case parseError(String)

    var displayMessage: String {
        switch self {
        case .toolchainNotFound:
            return "xcodebuild not found. Install Xcode to enable run controls."
        case .spawnFailed(let description):
            return "Failed to launch xcodebuild: \(description)"
        case .nonZeroExit(let code, let stderr):
            let snippet = stderr.prefix(200)
            return "xcodebuild exited with code \(code): \(snippet)"
        case .parseError(let description):
            return "Couldn't parse xcodebuild output: \(description)"
        }
    }
}

nonisolated protocol XcodeProcessRunning: Sendable {
    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> XcodeSpawnResult
    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32
}

nonisolated struct ProductionXcodeProcessRunner: XcodeProcessRunning {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> XcodeSpawnResult {
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
        // waitUntilExit() spins a CFRunLoop on the calling thread; on the Swift
        // cooperative pool that wakeup races with Foundation's child-monitoring
        // queue and is lost, blocking forever. terminationHandler fires on
        // Foundation's own queue. Same fix as #00057's git runner; #00058 here.
        let termination = XcodeProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw XcodeProcessRunnerError.spawnFailed(error.localizedDescription)
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
            return XcodeSpawnResult(exitCode: code, stdout: out, stderr: err)
        } onCancel: {
            Self.cancelProcess(process)
        }
    }

    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // Await exit via terminationHandler, not waitUntilExit() — same
        // cooperative-pool deadlock fix as run() above (#00057 / #00058).
        let termination = XcodeProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw XcodeProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        let handle = pipe.fileHandleForReading
        let buffer = XcodeLineBuffer()
        let stream = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            // readabilityHandler fires on an OS-provided background thread
            // outside the Swift Concurrency cooperative pool, and its closure
            // type isn't @Sendable — the compiler does not check captures here.
            // We enforce Sendability by hand: buffer is @unchecked Sendable
            // (NSLock-protected), continuation is Sendable. Don't add captures
            // without verifying that contract.
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if data.isEmpty {
                    if let final = buffer.flush() { continuation.yield(final) }
                    continuation.finish()
                    return
                }
                for line in buffer.append(data) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }

        return try await withTaskCancellationHandler {
            for await line in stream {
                onLine(line)
            }
            // Stream EOF means the child closed its pipe ends, i.e. it has
            // exited; terminationHandler has fired (or is about to) — the box
            // resolves either ordering race-free.
            let code = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                termination.attach(continuation)
            }
            if Task.isCancelled { throw CancellationError() }
            return code
        } onCancel: {
            Self.cancelProcess(process)
        }
    }

    static func cancelProcess(_ process: Process) {
        // SIGTERM → 2 s grace → SIGKILL. The `process.isRunning` re-check
        // after the sleep is load-bearing: it closes the PID-recycling race
        // (kernel can hand the same pid to an unrelated process once Foundation
        // has reaped our child). Double-scheduling this task (rapid cancel/run
        // cycles) is harmless — the second SIGKILL no-ops because the first
        // run already cleared isRunning. See notes.md 2026-05-15 (#00019).
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
// (#00057 root cause, #00058 applies the fix to the Xcode runner). Per-domain
// copy of GitProcessTermination — decisions.md 2026-05-25 #00042 keeps the
// subprocess runners duplicated per domain rather than extracting a shared box.
nonisolated final class XcodeProcessTermination: Sendable {
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

// Duplicated from ClaudeSession.LineBuffer per spec: extraction to a shared
// helper waits until a third caller justifies the indirection.
nonisolated final class XcodeLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var partial: String = ""

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let chunk = String(data: data, encoding: .utf8) else { return [] }
        partial.append(contentsOf: chunk)
        var lines: [String] = []
        lines.reserveCapacity(4)
        while let nl = partial.range(of: "\n") {
            lines.append(String(partial[..<nl.lowerBound]))
            partial.removeSubrange(..<nl.upperBound)
        }
        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let remaining = partial
        partial = ""
        return remaining.isEmpty ? nil : remaining
    }
}
