import Darwin
import Foundation
import os

// Streaming counterpart to GitProcessRunning. The batched runner buffers all
// stdout/stderr until the process exits — fine for `git diff` / `git status`,
// not fine for `git push` where the UI wants to see each line ("Counting
// objects…", "Writing objects…") as it arrives. This protocol returns a
// merged AsyncStream<StreamLine> of stdout + stderr plus a final exit code.
nonisolated enum GitStreamLineSource: Sendable, Equatable {
    case stdout
    case stderr
}

nonisolated struct GitStreamLine: Sendable, Equatable {
    let source: GitStreamLineSource
    let text: String
}

nonisolated struct GitStreamOutcome: Sendable, Equatable {
    let exitCode: Int32
}

nonisolated protocol GitProcessStreaming: Sendable {
    // Spawns git and returns a live AsyncStream of lines. The stream
    // finishes after the process exits; the awaitFinal() task resolves with
    // the exit code (or throws if the process couldn't be spawned).
    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?
    ) async throws -> (AsyncStream<GitStreamLine>, () async -> GitStreamOutcome)
}

// Production implementation. Mirrors ProductionGitProcessRunner's cancellation
// pattern (SIGTERM → 2s grace → SIGKILL) but reads from the pipes
// line-by-line via FileHandle.bytes.lines instead of waiting for EOF.
nonisolated struct ProductionGitProcessStreamer: GitProcessStreaming {
    static let cancellationGraceSeconds: TimeInterval = 2.0

    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?
    ) async throws -> (AsyncStream<GitStreamLine>, () async -> GitStreamOutcome) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Push/pull can't satisfy a TTY prompt anyway — feed /dev/null so
        // any credential prompt errors out immediately on stderr instead of
        // hanging the subprocess (we detect the error pattern downstream).
        process.standardInput = FileHandle.nullDevice

        // Same fix as ProductionGitProcessRunner (#00057): await exit via
        // terminationHandler, not Task.detached { waitUntilExit() }. The latter
        // spins a CFRunLoop on a cooperative-pool thread whose wakeup races with
        // Foundation's child-monitoring queue and is lost, hanging forever.
        let termination = GitProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw GitProcessRunnerError.spawnFailed(error.localizedDescription)
        }

        let (lineStream, lineCont) = AsyncStream<GitStreamLine>.makeStream()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Two detached readers, one per pipe. Each finishes when the pipe
        // closes (process exits or our cancellation kills it). A counter
        // tracks "both readers done" to close the merged stream.
        let pipeDone = PipeDoneCounter()
        Task.detached {
            for try await line in stdoutHandle.bytes.lines {
                lineCont.yield(GitStreamLine(source: .stdout, text: line))
            }
            await pipeDone.markDone(streamer: lineCont)
        }
        Task.detached {
            for try await line in stderrHandle.bytes.lines {
                lineCont.yield(GitStreamLine(source: .stderr, text: line))
            }
            await pipeDone.markDone(streamer: lineCont)
        }

        // Wire cancellation: if the parent Task is cancelled, terminate the
        // child process so the readers above see EOF and the stream closes.
        lineCont.onTermination = { @Sendable termination in
            if case .cancelled = termination {
                Self.cancelProcess(process)
            }
        }

        // Outcome awaitable — resolves from the terminationHandler set above.
        let outcome: @Sendable () async -> GitStreamOutcome = {
            let code = await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
                termination.attach(cont)
            }
            return GitStreamOutcome(exitCode: code)
        }

        return (lineStream, outcome)
    }

    static func cancelProcess(_ process: Process) {
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

// Closes the merged line stream once both pipe readers have finished.
private actor PipeDoneCounter {
    private var done = 0

    func markDone(streamer: AsyncStream<GitStreamLine>.Continuation) {
        done += 1
        if done == 2 { streamer.finish() }
    }
}

// In-memory mock that replays a scripted sequence of lines and a chosen exit
// code. Lines are emitted in order; the outcome resolves with `exitCode`
// after the stream finishes. Used by GitPushRunner/GitPullRunner tests to
// drive auth-prompt-detection and set-upstream-retry scenarios.
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
