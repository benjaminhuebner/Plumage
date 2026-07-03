import Foundation

@testable import Plumage

// @unchecked Sendable because the conformance is enforced manually via NSLock:
// the outcome store is mutated under `lock`, so concurrent access from test
// setup and the async-called protocol method is safe.
final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    enum DetectOutcome: Sendable {
        case success(VersionCheck)
        case failure(ProcessRunnerError)
    }

    private let lock = NSLock()
    private var _detectOutcome: DetectOutcome

    var detectOutcome: DetectOutcome {
        get { lock.withLock { _detectOutcome } }
        set { lock.withLock { _detectOutcome = newValue } }
    }

    init(detectOutcome: DetectOutcome = .failure(.binaryNotFound)) {
        self._detectOutcome = detectOutcome
    }

    func detectVersion() async throws -> VersionCheck {
        switch detectOutcome {
        case .success(let check): return check
        case .failure(let error): throw error
        }
    }
}
