import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ClaudeUsageModel")
struct ClaudeUsageModelTests {
    @Test("loading → loggedOut when keychain has no token")
    func loadingToLoggedOut() async {
        let model = ClaudeUsageModel()
        let client = ClaudeUsageClient(
            fetcher: StubHTTPFetcher(),
            keychain: MockKeychainReader(outcome: .failure(.notLoggedIn)),
            baseURLString: "https://claude.ai"
        )
        await model.refresh(using: client)
        #expect(model.isLoggedOut)
    }

    @Test("loading → usage on happy path")
    func loadingToUsage() async throws {
        let model = ClaudeUsageModel()
        let client = try await Self.happyPathClient()
        await model.refresh(using: client)
        if case .usage(let response) = model.state {
            #expect(response.fiveHour?.utilizationPct == 42.5)
        } else {
            Issue.record("expected .usage, got \(model.state)")
        }
        #expect(model.lastRefreshedAt != nil)
    }

    @Test("usage survives transient transport failure")
    func usageSurvivesFailure() async throws {
        let model = ClaudeUsageModel()
        let stub = StubHTTPFetcher()
        let token = OAuthToken(value: "sk-cache", expiresAt: nil)
        let keychain = MockKeychainReader(outcome: .token(token))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Self.orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 200, body: Self.usageJSON),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        let client = ClaudeUsageClient(
            fetcher: stub, keychain: keychain, baseURLString: "https://claude.ai")
        await model.refresh(using: client)

        stub.setOutcome(
            .failure(URLError(.notConnectedToInternet)),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        await model.refresh(using: client)
        if case .usage = model.state {
            // ok — last cache retained
        } else {
            Issue.record("expected usage to be retained, got \(model.state)")
        }
    }

    @Test("401 from server flips back to loggedOut even after usage was cached")
    func unauthorizedFlipsToLoggedOut() async throws {
        let model = ClaudeUsageModel()
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-prev", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Self.orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 200, body: Self.usageJSON),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        let client = ClaudeUsageClient(
            fetcher: stub, keychain: keychain, baseURLString: "https://claude.ai")
        await model.refresh(using: client)

        stub.setOutcome(
            .response(status: 401, body: Data()),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        await model.refresh(using: client)
        #expect(model.isLoggedOut)
    }

    private static func happyPathClient() async throws -> ClaudeUsageClient {
        let stub = StubHTTPFetcher()
        let token = OAuthToken(value: "sk-test", expiresAt: nil)
        let keychain = MockKeychainReader(outcome: .token(token))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 200, body: usageJSON),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        return ClaudeUsageClient(
            fetcher: stub, keychain: keychain, baseURLString: "https://claude.ai")
    }

    private static let orgsJSON: Data = Data(
        #"""
        [{ "uuid": "org-uuid", "name": "Plumage Org" }]
        """#.utf8)

    private static let usageJSON: Data = Data(
        #"""
        {
          "five_hour": { "utilization_pct": 42.5, "resets_at": "2026-05-20T22:00:00Z" },
          "seven_day": { "utilization_pct": 13.0, "resets_at": "2026-05-26T18:00:00Z" }
        }
        """#.utf8)
}
