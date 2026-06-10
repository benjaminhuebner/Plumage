import Foundation

@testable import Plumage

// @unchecked Sendable because the conformance is enforced manually via NSLock:
// outcome stores and the spawn callback are mutated under `lock`, so concurrent
// access from test setup and the async-called protocol methods is safe.
final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    enum DetectOutcome: Sendable {
        case success(VersionCheck)
        case failure(ProcessRunnerError)
    }

    enum SpawnOutcome: Sendable {
        case success(SpawnResult)
        case failure(ProcessRunnerError)
    }

    private let lock = NSLock()
    private var _detectOutcome: DetectOutcome
    private var _spawnOutcome: SpawnOutcome
    private var _onSpawnSessionCalled: (@Sendable ([String]) -> Void)?

    var detectOutcome: DetectOutcome {
        get { lock.withLock { _detectOutcome } }
        set { lock.withLock { _detectOutcome = newValue } }
    }

    var spawnOutcome: SpawnOutcome {
        get { lock.withLock { _spawnOutcome } }
        set { lock.withLock { _spawnOutcome = newValue } }
    }

    var onSpawnSessionCalled: (@Sendable ([String]) -> Void)? {
        get { lock.withLock { _onSpawnSessionCalled } }
        set { lock.withLock { _onSpawnSessionCalled = newValue } }
    }

    init(
        detectOutcome: DetectOutcome = .failure(.binaryNotFound),
        spawnOutcome: SpawnOutcome = .success(SpawnResult(exitCode: 0, stdout: Data(), stderr: Data()))
    ) {
        self._detectOutcome = detectOutcome
        self._spawnOutcome = spawnOutcome
    }

    func detectVersion() async throws -> VersionCheck {
        switch detectOutcome {
        case .success(let check): return check
        case .failure(let error): throw error
        }
    }

    func spawnSession(args: [String]) async throws -> SpawnResult {
        onSpawnSessionCalled?(args)
        switch spawnOutcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
