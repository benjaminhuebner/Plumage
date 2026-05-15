import Foundation

@testable import Plumage

final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    enum DetectOutcome: Sendable {
        case success(VersionCheck)
        case failure(ProcessRunnerError)
    }

    enum SpawnOutcome: Sendable {
        case success(SpawnResult)
        case failure(ProcessRunnerError)
    }

    var detectOutcome: DetectOutcome
    var spawnOutcome: SpawnOutcome
    var onSpawnSessionCalled: (@Sendable ([String]) -> Void)?

    init(
        detectOutcome: DetectOutcome = .failure(.binaryNotFound),
        spawnOutcome: SpawnOutcome = .success(SpawnResult(exitCode: 0, stdout: Data(), stderr: Data()))
    ) {
        self.detectOutcome = detectOutcome
        self.spawnOutcome = spawnOutcome
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
