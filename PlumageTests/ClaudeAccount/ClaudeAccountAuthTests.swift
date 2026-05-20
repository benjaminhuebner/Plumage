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
    func mockPropagatesNotLoggedIn() {
        let reader = MockKeychainReader(outcome: .failure(.notLoggedIn))
        #expect(throws: ClaudeAccountAuthError.notLoggedIn) {
            _ = try reader.readToken()
        }
    }

    @Test("MockKeychainReader returns configured token")
    func mockReturnsToken() throws {
        let reader = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-mock", expiresAt: nil)))
        let token = try reader.readToken()
        #expect(token.value == "sk-mock")
    }
}
