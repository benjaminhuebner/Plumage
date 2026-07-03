import Foundation
import Testing

@testable import Plumage

@Suite("GitHubTokenVerifier")
struct GitHubTokenVerifierTests {
    private static let userJSON = Data(
        """
        {"login":"octocat","id":583231,"name":"The Octocat",
         "avatar_url":"https://avatars.githubusercontent.com/u/583231?v=4"}
        """.utf8)

    private func makeVerifier(_ stub: StubHTTPFetcher) -> GitHubTokenVerifier {
        GitHubTokenVerifier(fetcher: stub, endpoint: GitHubTokenVerifier.userEndpoint)
    }

    @Test("A valid token returns the user with parsed classic scopes")
    func validTokenClassicScopes() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(status: 200, body: Self.userJSON, headers: ["x-oauth-scopes": "repo, read:org"]),
            for: GitHubTokenVerifier.userEndpoint)
        let user = try await makeVerifier(stub).verify(token: "ghp_valid")
        #expect(user.login == "octocat")
        #expect(user.name == "The Octocat")
        #expect(user.avatarURL == URL(string: "https://avatars.githubusercontent.com/u/583231?v=4"))
        #expect(user.scopes == ["repo", "read:org"])
    }

    @Test("Required headers are sent on the request")
    func sendsRequiredHeaders() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Self.userJSON), for: GitHubTokenVerifier.userEndpoint)
        _ = try await makeVerifier(stub).verify(token: "ghp_valid")
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_valid")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test("A fine-grained token (no scopes header) yields empty scopes")
    func fineGrainedNoScopesHeader() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Self.userJSON), for: GitHubTokenVerifier.userEndpoint)
        let user = try await makeVerifier(stub).verify(token: "github_pat_x")
        #expect(user.scopes.isEmpty)
    }

    @Test("A 401 surfaces as .unauthorized")
    func unauthorized() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 401, body: Data()), for: GitHubTokenVerifier.userEndpoint)
        await #expect(throws: GitHubTokenVerifierError.unauthorized) {
            try await makeVerifier(stub).verify(token: "ghp_bad")
        }
    }

    @Test("A 500 surfaces as .serverError")
    func serverError() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 500, body: Data()), for: GitHubTokenVerifier.userEndpoint)
        await #expect(throws: GitHubTokenVerifierError.serverError(500)) {
            try await makeVerifier(stub).verify(token: "ghp_x")
        }
    }

    @Test("Malformed JSON on 200 surfaces as .unparseable")
    func unparseable() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Data("not json".utf8)), for: GitHubTokenVerifier.userEndpoint)
        await #expect(throws: GitHubTokenVerifierError.self) {
            try await makeVerifier(stub).verify(token: "ghp_x")
        }
    }

    @Test("Transport failures surface as .transport")
    func transportFailure() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.failure(URLError(.notConnectedToInternet)), for: GitHubTokenVerifier.userEndpoint)
        await #expect(throws: GitHubTokenVerifierError.self) {
            try await makeVerifier(stub).verify(token: "ghp_x")
        }
    }

    @Test("Scope-header parsing trims, splits, and drops empties")
    func scopeParsing() {
        #expect(GitHubTokenVerifier.parseScopes(nil).isEmpty)
        #expect(GitHubTokenVerifier.parseScopes("").isEmpty)
        #expect(GitHubTokenVerifier.parseScopes("   ").isEmpty)
        #expect(GitHubTokenVerifier.parseScopes("repo") == ["repo"])
        #expect(GitHubTokenVerifier.parseScopes("repo, read:org , ") == ["repo", "read:org"])
    }
}
