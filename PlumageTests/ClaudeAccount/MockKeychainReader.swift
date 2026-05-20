import Foundation

@testable import Plumage

// @unchecked Sendable: outcome mutated through NSLock; same rationale as
// MockProcessRunner in CCI (decisions.md 2026-05-15 #00019).
final class MockKeychainReader: KeychainReading, @unchecked Sendable {
    enum Outcome: Sendable {
        case token(OAuthToken)
        case failure(ClaudeAccountAuthError)
    }

    private let lock = NSLock()
    private var _outcome: Outcome

    init(outcome: Outcome = .failure(.notLoggedIn)) {
        self._outcome = outcome
    }

    var outcome: Outcome {
        get { lock.withLock { _outcome } }
        set { lock.withLock { _outcome = newValue } }
    }

    func readToken() throws -> OAuthToken {
        switch outcome {
        case .token(let token): return token
        case .failure(let error): throw error
        }
    }
}
