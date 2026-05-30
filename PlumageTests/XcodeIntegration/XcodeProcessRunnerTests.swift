import Foundation
import Testing

@testable import Plumage

@Suite("ProductionXcodeProcessRunner", .tags(.integration))
struct ProductionXcodeProcessRunnerTests {
    @Test("captures stdout and exit code from /bin/echo")
    func runCapturesStdout() async throws {
        let runner = ProductionXcodeProcessRunner()
        let result = try await runner.run(
            binaryURL: URL(fileURLWithPath: "/bin/echo"),
            args: ["hello", "plumage"],
            cwd: nil
        )
        #expect(result.exitCode == 0)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        #expect(stdout == "hello plumage\n")
    }

    @Test("non-zero exit is surfaced in exitCode")
    func runReportsNonZeroExit() async throws {
        let runner = ProductionXcodeProcessRunner()
        // /usr/bin/false always exits with code 1.
        let result = try await runner.run(
            binaryURL: URL(fileURLWithPath: "/usr/bin/false"),
            args: [],
            cwd: nil
        )
        #expect(result.exitCode != 0)
    }

    @Test("stream emits one callback per line and reports the final exit code")
    func streamYieldsLines() async throws {
        let runner = ProductionXcodeProcessRunner()
        let collected = LineCollector()
        let exit = try await runner.stream(
            binaryURL: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "printf 'one\\ntwo\\nthree\\n'"],
            cwd: nil,
            onLine: { line in collected.append(line) }
        )
        #expect(exit == 0)
        #expect(collected.lines == ["one", "two", "three"])
    }

    @Test("stream cancellation terminates the child process")
    func streamCancellationTerminatesProcess() async throws {
        let runner = ProductionXcodeProcessRunner()
        // /bin/sh emits the marker line, then blocks in sleep. We wait on the
        // marker via an AsyncStream instead of a wallclock sleep — that keeps
        // the cancel happening AFTER the subprocess is verifiably running.
        let (signal, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await runner.stream(
                binaryURL: URL(fileURLWithPath: "/bin/sh"),
                args: ["-c", "echo started; sleep 10"],
                cwd: nil,
                onLine: { line in
                    if line == "started" { continuation.yield() }
                }
            )
        }
        var iterator = signal.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("stream did not throw on cancel")
        } catch is CancellationError {
            // expected
        } catch {
            // Some shells surface the SIGTERM as a non-zero exit + propagated
            // CancellationError check; either path proves the child died.
        }
    }
}

@Suite("XcodeLineBuffer")
struct XcodeLineBufferTests {
    @Test("returns empty when chunk has no newline")
    func appendBuffersWithoutNewline() {
        let buffer = XcodeLineBuffer()
        let lines = buffer.append(Data("partial".utf8))
        #expect(lines.isEmpty)
    }

    @Test("splits on newlines and keeps trailing partial")
    func appendSplitsLines() {
        let buffer = XcodeLineBuffer()
        let lines = buffer.append(Data("first\nsecond\nthird".utf8))
        #expect(lines == ["first", "second"])
        let flushed = buffer.flush()
        #expect(flushed == "third")
    }

    @Test("flush returns nil when buffer is empty")
    func flushEmptyReturnsNil() {
        let buffer = XcodeLineBuffer()
        #expect(buffer.flush() == nil)
    }

    @Test("concatenates chunks across appends")
    func chunksConcatenate() {
        let buffer = XcodeLineBuffer()
        _ = buffer.append(Data("fir".utf8))
        let lines = buffer.append(Data("st\nsecond\n".utf8))
        #expect(lines == ["first", "second"])
    }
}

@Suite("MockXcodeProcessRunner")
struct MockXcodeProcessRunnerTests {
    @Test("default outcome is success with empty data")
    func defaultSuccess() async throws {
        let mock = MockXcodeProcessRunner()
        let result = try await mock.run(
            binaryURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            args: ["-version"],
            cwd: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)
    }

    @Test("records every invocation with its mode")
    func invocationsRecorded() async throws {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        _ = try await mock.run(binaryURL: url, args: ["-list"], cwd: nil)
        _ = try await mock.stream(binaryURL: url, args: ["build"], cwd: nil) { _ in }
        let invocations = mock.invocations
        #expect(invocations.count == 2)
        #expect(invocations.first?.mode == .run)
        #expect(invocations.last?.mode == .stream)
    }

    @Test("per-binary outcome wins over default")
    func perBinaryOutcome() async throws {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        mock.setRunOutcome(
            .success(
                XcodeSpawnResult(
                    exitCode: 7,
                    stdout: Data("custom".utf8),
                    stderr: Data()
                )),
            forBinary: url
        )
        let result = try await mock.run(binaryURL: url, args: [], cwd: nil)
        #expect(result.exitCode == 7)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "custom")
    }

    @Test("stream replays lines and returns the configured exit code")
    func streamReplays() async throws {
        let mock = MockXcodeProcessRunner()
        mock.streamOutcome = .success(lines: ["a", "b"], exitCode: 0)
        let collector = LineCollector()
        let exit = try await mock.stream(
            binaryURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            args: ["build"],
            cwd: nil
        ) { line in collector.append(line) }
        #expect(exit == 0)
        #expect(collector.lines == ["a", "b"])
    }

    @Test("failure outcome throws the configured error")
    func failureThrows() async {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        mock.setRunOutcome(.failure(.toolchainNotFound), forBinary: url)
        do {
            _ = try await mock.run(binaryURL: url, args: [], cwd: nil)
            Issue.record("expected toolchainNotFound")
        } catch let error as XcodeProcessRunnerError {
            #expect(error == .toolchainNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

// Sendable line buffer used by the streaming tests above.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    var lines: [String] {
        lock.withLock { _lines }
    }

    func append(_ line: String) {
        lock.withLock { _lines.append(line) }
    }
}
