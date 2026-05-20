import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeUsageClient")
struct ClaudeUsageClientTests {
    @Test("happy path: resolves org then fetches usage")
    func happyPath() async throws {
        let stub = StubHTTPFetcher()
        let token = OAuthToken(value: "sk-test", expiresAt: nil)
        let keychain = MockKeychainReader(outcome: .token(token))

        let baseURL = try #require(URL(string: "https://claude.ai"))
        let orgsURL = baseURL.appending(path: "/api/organizations")
        let usageURL = baseURL.appending(path: "/api/organizations/org-uuid/usage")

        stub.setOutcome(.response(status: 200, body: Self.orgsJSON), for: orgsURL)
        stub.setOutcome(.response(status: 200, body: Self.usageJSON), for: usageURL)

        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )

        let response = try await client.fetchUsage()
        #expect(response.fiveHour?.utilizationPct == 42.5)

        let bearer = stub.requests.compactMap {
            $0.value(forHTTPHeaderField: "Authorization")
        }
        #expect(bearer.allSatisfy { $0 == "Bearer sk-test" })
        #expect(bearer.count == 2)
    }

    @Test("organization ID is cached after first call")
    func cachesOrgID() async throws {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-cache", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        let orgsURL = baseURL.appending(path: "/api/organizations")
        let usageURL = baseURL.appending(path: "/api/organizations/org-uuid/usage")
        stub.setOutcome(.response(status: 200, body: Self.orgsJSON), for: orgsURL)
        stub.setOutcome(.response(status: 200, body: Self.usageJSON), for: usageURL)

        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )

        _ = try await client.fetchUsage()
        _ = try await client.fetchUsage()
        let orgCalls = stub.requests.filter { $0.url == orgsURL }
        #expect(orgCalls.count == 1)
    }

    @Test("401 from usage endpoint maps to notLoggedIn")
    func mapsUnauthorized() async throws {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-stale", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Self.orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 401, body: Data()),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))

        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )
        await #expect(throws: ClaudeUsageError.notLoggedIn) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("5xx maps to serverError")
    func mapsServerError() async throws {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-srv", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Self.orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 503, body: Data()),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))

        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )
        await #expect(throws: ClaudeUsageError.serverError(503)) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("missing keychain token maps to notLoggedIn")
    func mapsMissingToken() async {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(outcome: .failure(.notLoggedIn))
        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )
        await #expect(throws: ClaudeUsageError.notLoggedIn) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("empty org listing maps to noOrganization")
    func mapsNoOrg() async throws {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-none", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Data("[]".utf8)),
            for: baseURL.appending(path: "/api/organizations"))
        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )
        await #expect(throws: ClaudeUsageError.noOrganization) {
            _ = try await client.fetchUsage()
        }
    }

    @Test("malformed usage body maps to unparseable")
    func mapsUnparseable() async throws {
        let stub = StubHTTPFetcher()
        let keychain = MockKeychainReader(
            outcome: .token(OAuthToken(value: "sk-bad", expiresAt: nil)))
        let baseURL = try #require(URL(string: "https://claude.ai"))
        stub.setOutcome(
            .response(status: 200, body: Self.orgsJSON),
            for: baseURL.appending(path: "/api/organizations"))
        stub.setOutcome(
            .response(status: 200, body: Data("not json".utf8)),
            for: baseURL.appending(path: "/api/organizations/org-uuid/usage"))
        let client = ClaudeUsageClient(
            fetcher: stub,
            keychain: keychain,
            baseURLString: "https://claude.ai"
        )
        await #expect(throws: ClaudeUsageError.self) {
            _ = try await client.fetchUsage()
        }
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
