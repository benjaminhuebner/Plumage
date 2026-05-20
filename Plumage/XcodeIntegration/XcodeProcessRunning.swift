import Darwin
import Foundation

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

        do {
            try process.run()
        } catch {
            throw XcodeProcessRunnerError.spawnFailed(error.localizedDescription)
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

        do {
            try process.run()
        } catch {
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
            async let exit: Int32 = Task.detached {
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            for await line in stream {
                onLine(line)
            }
            let code = await exit
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
