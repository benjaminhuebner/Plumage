import Foundation

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

// Production implementation. Shares ProductionGitProcessRunner's cancellation
// (SIGTERM → grace → SIGKILL) but reads from the pipes line-by-line via
// FileHandle.bytes.lines instead of waiting for EOF.
nonisolated struct ProductionGitProcessStreamer: GitProcessStreaming {
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

        // Same fix as ProductionGitProcessRunner: await exit via
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
        // markDone must fire even when bytes.lines throws (read error mid-
        // stream) — a skipped markDone leaves the merged stream open and the
        // consumer awaiting the outcome forever.
        let pipeDone = PipeDoneCounter()
        Task.detached {
            do {
                for try await line in stdoutHandle.bytes.lines {
                    lineCont.yield(GitStreamLine(source: .stdout, text: line))
                }
            } catch {}
            await pipeDone.markDone(streamer: lineCont)
        }
        Task.detached {
            do {
                for try await line in stderrHandle.bytes.lines {
                    lineCont.yield(GitStreamLine(source: .stderr, text: line))
                }
            } catch {}
            await pipeDone.markDone(streamer: lineCont)
        }

        // Wire cancellation: if the parent Task is cancelled, terminate the
        // child process so the readers above see EOF and the stream closes.
        lineCont.onTermination = { @Sendable termination in
            if case .cancelled = termination {
                ProductionGitProcessRunner.cancelProcess(process)
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
}

// Closes the merged line stream once both pipe readers have finished.
private actor PipeDoneCounter {
    private var done = 0

    func markDone(streamer: AsyncStream<GitStreamLine>.Continuation) {
        done += 1
        if done == 2 { streamer.finish() }
    }
}
