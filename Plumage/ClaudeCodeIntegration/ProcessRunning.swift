import Darwin
import Foundation

nonisolated protocol ProcessRunning: Sendable {
    func detectVersion() async throws -> VersionCheck
    func spawnSession(args: [String]) async throws -> SpawnResult
}

nonisolated struct ProductionProcessRunner: ProcessRunning {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func detectVersion() async throws -> VersionCheck {
        let binary = try Self.locateBinary()
        let result = try await Self.spawnAt(binaryURL: binary, args: ["--version"])
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        let stdoutString = String(decoding: result.stdout, as: UTF8.self)
        guard let version = SemanticVersion.parse(stdoutString) else {
            throw ProcessRunnerError.parseError(stdoutString)
        }
        return VersionCheck(
            version: version,
            binaryURL: binary,
            inSupportedRange: SupportedClaudeVersion.inSupportedRange(version)
        )
    }

    func spawnSession(args: [String]) async throws -> SpawnResult {
        let binary = try Self.locateBinary()
        return try await Self.spawnAt(binaryURL: binary, args: args)
    }

    // MARK: - Binary discovery

    static func locateBinary() throws(ProcessRunnerError) -> URL {
        if let viaPath = try? whichClaude() {
            return viaPath
        }
        let homeLocal = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/local/claude")
        if FileManager.default.isExecutableFile(atPath: homeLocal.path) {
            return homeLocal
        }
        throw .binaryNotFound
    }

    private static func whichClaude() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.binaryNotFound
        }
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let raw = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw ProcessRunnerError.binaryNotFound
        }
        return URL(fileURLWithPath: raw)
    }

    // MARK: - Spawning

    // Internal access so integration tests can drive the spawn machinery with
    // /bin/echo and /bin/sleep without going through locateBinary().
    static func spawnAt(binaryURL: URL, args: [String]) async throws -> SpawnResult {
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

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            // Drain stdout/stderr in parallel with waitUntilExit to avoid pipe-buffer deadlock.
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
            if Task.isCancelled {
                throw CancellationError()
            }
            return SpawnResult(exitCode: code, stdout: out, stderr: err)
        } onCancel: {
            // SIGTERM via Foundation, escalating to SIGKILL after grace period.
            if process.isRunning {
                process.terminate()
            }
            let pid = process.processIdentifier
            Task.detached { [process] in
                try? await Task.sleep(for: .seconds(Self.cancellationGraceSeconds))
                // Re-check isRunning to avoid SIGKILL on a recycled PID once
                // waitUntilExit has reaped the child after the SIGTERM landed.
                if pid > 0, process.isRunning {
                    _ = Darwin.kill(pid, SIGKILL)
                }
            }
        }
    }
}
