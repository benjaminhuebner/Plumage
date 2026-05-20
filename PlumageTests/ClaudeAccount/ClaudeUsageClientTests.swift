import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeUsageClient")
struct ClaudeUsageClientTests {
    @Test("happy path: bearer-auth + version header against single usage endpoint")
    func happyPath() async throws {
        let stub = StubHTTPFetcher()
        let token = OAuthToken(value: "sk-test", expiresAt: nil)
        let keychain = MockKeychainReader(outcome: .token(token))
        stub.setOutcome(.response(status: 200, body: Self.usageJSON), for: ClaudeUsageClient.usageEndpoint)
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        let response = try await client.fetchUsage()
        #expect(response.fiveHour?.utilizationPct == 42.5)
        #expect(stub.requests.count == 1)
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test("401 maps to notLoggedIn")
    func mapsUnauthorized() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .token(OAuthToken(value: "sk-stale", expiresAt: nil)))
        stub.setDefault(.response(status: 401, body: Data()))
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        await #expect(throws: ClaudeUsageError.notLoggedIn) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("403 maps to notLoggedIn")
    func mapsForbidden() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .token(OAuthToken(value: "sk-forb", expiresAt: nil)))
        stub.setDefault(.response(status: 403, body: Data()))
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        await #expect(throws: ClaudeUsageError.notLoggedIn) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("5xx maps to serverError")
    func mapsServerError() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .token(OAuthToken(value: "sk-srv", expiresAt: nil)))
        stub.setDefault(.response(status: 503, body: Data()))
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        await #expect(throws: ClaudeUsageError.serverError(503)) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("missing keychain token maps to notLoggedIn")
    func mapsMissingToken() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .failure(.notLoggedIn))
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        await #expect(throws: ClaudeUsageError.notLoggedIn) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("malformed body maps to unparseable")
    func mapsUnparseable() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .token(OAuthToken(value: "sk-bad", expiresAt: nil)))
        stub.setOutcome(.response(status: 200, body: Data("not json".utf8)), for: ClaudeUsageClient.usageEndpoint)
        let client = ClaudeUsageClient(fetcher: stub, keychain: keychain)
        await #expect(throws: ClaudeUsageError.self) {
            _ = try await client.fetchUsage()
        }
    }

    private static let usageJSON: Data = Data(
        #"""
        {
          "five_hour": { "utilization": 42.5, "resets_at": "2026-05-20T22:00:00Z" },
          "seven_day": { "utilization": 13.0, "resets_at": "2026-05-26T18:00:00Z" }
        }
        """#.utf8)
}
