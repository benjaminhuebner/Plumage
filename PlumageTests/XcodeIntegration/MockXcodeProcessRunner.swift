import Foundation

@testable import Plumage

// @unchecked Sendable: outcomes and the streamed-lines vector are mutated
// through NSLock; same rationale as MockProcessRunner in CCI.
final class MockXcodeProcessRunner: XcodeProcessRunning, @unchecked Sendable {
    struct Invocation: Sendable, Equatable {
        let binaryURL: URL
        let args: [String]
        let cwd: URL?
        let mode: Mode

        enum Mode: Sendable, Equatable {
            case run
            case stream
        }
    }

    enum RunOutcome: Sendable {
        case success(XcodeSpawnResult)
        case failure(XcodeProcessRunnerError)
    }

    enum StreamOutcome: Sendable {
        case success(lines: [String], exitCode: Int32)
        case failure(XcodeProcessRunnerError)
    }

    private let lock = NSLock()
    private var _runOutcomes: [URL: RunOutcome] = [:]
    private var _defaultRunOutcome: RunOutcome = .success(
        XcodeSpawnResult(exitCode: 0, stdout: Data(), stderr: Data()))
    private var _streamOutcome: StreamOutcome = .success(lines: [], exitCode: 0)
    private var _invocations: [Invocation] = []

    var runOutcomes: [URL: RunOutcome] {
        get { lock.withLock { _runOutcomes } }
        set { lock.withLock { _runOutcomes = newValue } }
    }

    var defaultRunOutcome: RunOutcome {
        get { lock.withLock { _defaultRunOutcome } }
        set { lock.withLock { _defaultRunOutcome = newValue } }
    }

    var streamOutcome: StreamOutcome {
        get { lock.withLock { _streamOutcome } }
        set { lock.withLock { _streamOutcome = newValue } }
    }

    var invocations: [Invocation] {
        lock.withLock { _invocations }
    }

    func setRunOutcome(_ outcome: RunOutcome, forBinary binaryURL: URL) {
        lock.withLock { _runOutcomes[binaryURL] = outcome }
    }

    func clearInvocations() {
        lock.withLock { _invocations.removeAll() }
    }

    func run(binaryURL: URL, args: [String], cwd: URL?) async throws -> XcodeSpawnResult {
        let outcome: RunOutcome = lock.withLock {
            _invocations.append(
                Invocation(binaryURL: binaryURL, args: args, cwd: cwd, mode: .run))
            return _runOutcomes[binaryURL] ?? _defaultRunOutcome
        }
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    func stream(
        binaryURL: URL,
        args: [String],
        cwd: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let outcome: StreamOutcome = lock.withLock {
            _invocations.append(
                Invocation(binaryURL: binaryURL, args: args, cwd: cwd, mode: .stream))
            return _streamOutcome
        }
        switch outcome {
        case .success(let lines, let exitCode):
            for line in lines { onLine(line) }
            return exitCode
        case .failure(let error):
            throw error
        }
    }
}
