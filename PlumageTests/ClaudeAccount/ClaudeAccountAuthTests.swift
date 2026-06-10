import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeAccountAuth keychain payload decoder")
struct ClaudeAccountAuthTests {
    @Test("decodes nested claudeAiOauth envelope with millisecond expiry")
    func decodesNestedEnvelope() throws {
        let json = #"""
            {
              "claudeAiOauth": {
                "accessToken": "sk-abc",
                "expiresAt": 1747780000000
              }
            }
            """#
        let token = try ProductionKeychainReader.decode(data: Data(json.utf8))
        #expect(token.value == "sk-abc")
        let expected = Date(timeIntervalSince1970: 1_747_780_000)
        #expect(token.expiresAt?.timeIntervalSince1970 == expected.timeIntervalSince1970)
    }

    @Test("decodes flat snake_case envelope")
    func decodesFlatEnvelope() throws {
        let json = #"""
            { "access_token": "sk-flat", "expires_in": 3600 }
            """#
        let token = try ProductionKeychainReader.decode(data: Data(json.utf8))
        #expect(token.value == "sk-flat")
        let expiresAt = try #require(token.expiresAt)
        let drift = abs(expiresAt.timeIntervalSinceNow - 3600)
        #expect(drift < 2)
    }

    @Test("decodes flat camelCase envelope")
    func decodesCamelCase() throws {
        let json = #"""
            { "accessToken": "sk-camel" }
            """#
        let token = try ProductionKeychainReader.decode(data: Data(json.utf8))
        #expect(token.value == "sk-camel")
        #expect(token.expiresAt == nil)
    }

    @Test("decodes raw token string")
    func decodesRawString() throws {
        let raw = "sk-raw-12345"
        let token = try ProductionKeychainReader.decode(data: Data(raw.utf8))
        #expect(token.value == "sk-raw-12345")
        #expect(token.expiresAt == nil)
    }

    @Test("rejects empty payload")
    func rejectsEmpty() {
        #expect(throws: ClaudeAccountAuthError.self) {
            _ = try ProductionKeychainReader.decode(data: Data())
        }
    }

    @Test("rejects JSON envelope without a token field")
    func rejectsEnvelopeWithoutToken() {
        let json = #"""
            { "expiresAt": 1747780000000 }
            """#
        #expect(throws: ClaudeAccountAuthError.self) {
            _ = try ProductionKeychainReader.decode(data: Data(json.utf8))
        }
    }

    @Test("MockKeychainReader propagates notLoggedIn")
    func mockPropagatesNotLoggedIn() async {
        let reader = MockKeychainReader(outcome: .failure(.notLoggedIn))
        await #expect(throws: ClaudeAccountAuthError.notLoggedIn) {
            _ = try await reader.readToken()
        }
    }

    @Test("MockKeychainReader returns configured token")
    func mockReturnsToken() async throws {
        let reader = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-mock", expiresAt: nil)))
        let token = try await reader.readToken()
        #expect(token.value == "sk-mock")
    }
}

private struct StubServiceDiscovery: KeychainServiceDiscovering {
    let candidates: [KeychainServiceCandidate]

    func candidateServices(prefix: String) -> [KeychainServiceCandidate] {
        candidates.filter { $0.service.hasPrefix(prefix) }
    }
}

@Suite("ProductionKeychainReader subprocess read")
struct ProductionKeychainReaderTests {
    private static func args(service: String) -> [String] {
        ["find-generic-password", "-s", service, "-a", NSUserName(), "-w"]
    }

    private static let readArgs = args(service: ClaudeKeychain.serviceName)

    private func reader(
        _ mock: MockSecurityToolRunner,
        discovery: StubServiceDiscovery = StubServiceDiscovery(candidates: [])
    ) -> ProductionKeychainReader {
        ProductionKeychainReader(runner: mock, discovery: discovery)
    }

    @Test("exit 44 maps to notLoggedIn")
    func exit44MapsToNotLoggedIn() async {
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: ClaudeKeychain.itemNotFoundExit]
        await #expect(throws: ClaudeAccountAuthError.notLoggedIn) {
            _ = try await reader(mock).readToken()
        }
    }

    @Test("empty stdout with exit 0 maps to notLoggedIn")
    func emptyStdoutMapsToNotLoggedIn() async {
        let mock = MockSecurityToolRunner()
        mock.stdoutForArgs = [Self.readArgs: "\n"]
        await #expect(throws: ClaudeAccountAuthError.notLoggedIn) {
            _ = try await reader(mock).readToken()
        }
    }

    @Test("timeout surfaces readFailed without hanging")
    func timeoutSurfacesReadFailed() async {
        let mock = MockSecurityToolRunner()
        mock.error = .timedOut
        await #expect(throws: ClaudeAccountAuthError.readFailed("security timed out")) {
            _ = try await reader(mock).readToken()
        }
    }

    @Test("unexpected exit code surfaces readFailed")
    func unexpectedExitSurfacesReadFailed() async {
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: 1]
        await #expect(throws: ClaudeAccountAuthError.readFailed("security exited with code 1")) {
            _ = try await reader(mock).readToken()
        }
    }

    @Test("decodes JSON payload with trailing newline")
    func decodesPayloadWithTrailingNewline() async throws {
        let mock = MockSecurityToolRunner()
        mock.stdoutForArgs = [
            Self.readArgs: #"{ "claudeAiOauth": { "accessToken": "sk-live" } }"# + "\n"
        ]
        let token = try await reader(mock).readToken()
        #expect(token.value == "sk-live")
        #expect(mock.recordedCalls == [Self.readArgs])
    }

    @Test("falls back to discovered hashed service name when legacy is missing")
    func hashedFallbackResolves() async throws {
        let hashed = "\(ClaudeKeychain.serviceName)-abc123"
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: ClaudeKeychain.itemNotFoundExit]
        mock.stdoutForArgs = [Self.args(service: hashed): #"{ "accessToken": "sk-hashed" }"#]
        let discovery = StubServiceDiscovery(candidates: [
            KeychainServiceCandidate(service: hashed, modifiedAt: nil)
        ])
        let token = try await reader(mock, discovery: discovery).readToken()
        #expect(token.value == "sk-hashed")
        #expect(mock.recordedCalls == [Self.readArgs, Self.args(service: hashed)])
    }

    @Test("multiple hashed candidates resolve to the most recently modified")
    func hashedFallbackPicksMostRecent() async throws {
        let older = "\(ClaudeKeychain.serviceName)-old"
        let newer = "\(ClaudeKeychain.serviceName)-new"
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: ClaudeKeychain.itemNotFoundExit]
        mock.stdoutForArgs = [Self.args(service: newer): #"{ "accessToken": "sk-new" }"#]
        let discovery = StubServiceDiscovery(candidates: [
            KeychainServiceCandidate(service: older, modifiedAt: Date(timeIntervalSince1970: 100)),
            KeychainServiceCandidate(service: newer, modifiedAt: Date(timeIntervalSince1970: 200)),
        ])
        let token = try await reader(mock, discovery: discovery).readToken()
        #expect(token.value == "sk-new")
    }

    @Test("no hashed candidates maps to notLoggedIn")
    func noCandidatesMapsToNotLoggedIn() async {
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: ClaudeKeychain.itemNotFoundExit]
        await #expect(throws: ClaudeAccountAuthError.notLoggedIn) {
            _ = try await reader(mock).readToken()
        }
    }

    @Test("resolved hashed name is pinned for subsequent reads")
    func resolvedNamePinned() async throws {
        let hashed = "\(ClaudeKeychain.serviceName)-abc123"
        let hashedArgs = Self.args(service: hashed)
        let mock = MockSecurityToolRunner()
        mock.exitCodeForArgs = [Self.readArgs: ClaudeKeychain.itemNotFoundExit]
        mock.stdoutForArgs = [hashedArgs: #"{ "accessToken": "sk-hashed" }"#]
        let discovery = StubServiceDiscovery(candidates: [
            KeychainServiceCandidate(service: hashed, modifiedAt: nil)
        ])
        let keychainReader = reader(mock, discovery: discovery)
        _ = try await keychainReader.readToken()
        _ = try await keychainReader.readToken()
        #expect(mock.recordedCalls == [Self.readArgs, hashedArgs, hashedArgs])
    }
}
