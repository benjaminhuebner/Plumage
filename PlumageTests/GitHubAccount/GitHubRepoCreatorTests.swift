import Foundation
import Testing

@testable import Plumage

@Suite("GitHubRepoCreator")
struct GitHubRepoCreatorTests {
    private static let createdJSON = Data(
        """
        {"full_name":"octocat/hello","private":true,
         "clone_url":"https://github.com/octocat/hello.git"}
        """.utf8)

    private func makeCreator(_ stub: StubHTTPFetcher) -> GitHubRepoCreator {
        GitHubRepoCreator(fetcher: stub, endpoint: GitHubRepoCreator.reposEndpoint)
    }

    private func createExpectingError(_ stub: StubHTTPFetcher) async -> GitHubRepoCreatorError? {
        await #expect(throws: GitHubRepoCreatorError.self) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("A 201 with clone_url returns the parsed HTTPS remote")
    func createdReturnsCloneURL() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        let repo = try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        #expect(repo.cloneURL == URL(string: "https://github.com/octocat/hello.git"))
        #expect(repo.fullName == "octocat/hello")
    }

    @Test("The request is a POST with the GitHub headers and a name/private body")
    func requestShape() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        _ = try await makeCreator(stub).createRepo(name: "hello", isPrivate: false, token: "ghp_x")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_x")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "hello")
        #expect(json["private"] as? Bool == false)
        // No auto-init / README so the local history can't diverge.
        #expect(json["auto_init"] == nil)
    }

    @Test("The private flag rides through as true")
    func privateFlagTrue() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        _ = try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        let body = try #require(stub.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["private"] as? Bool == true)
    }

    @Test("A 422 surfaces nameAlreadyExists with the GitHub message")
    func nameTaken() async {
        let stub = StubHTTPFetcher()
        let body = Data(
            """
            {"message":"Repository creation failed.",
             "errors":[{"resource":"Repository","field":"name",
             "message":"name already exists on this account"}]}
            """.utf8)
        stub.setOutcome(.response(status: 422, body: body), for: GitHubRepoCreator.reposEndpoint)
        await #expect(
            throws: GitHubRepoCreatorError.nameAlreadyExists("name already exists on this account")
        ) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("A 403 maps to insufficientScopes")
    func forbiddenScopes() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 403, body: Data()), for: GitHubRepoCreator.reposEndpoint)
        await #expect(throws: GitHubRepoCreatorError.insufficientScopes) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("A 404 maps to insufficientScopes")
    func notFoundScopes() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 404, body: Data()), for: GitHubRepoCreator.reposEndpoint)
        await #expect(throws: GitHubRepoCreatorError.insufficientScopes) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("A rate-limit 403 maps to rateLimited, not insufficientScopes")
    func rateLimited403() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(
                status: 403,
                body: Data("{\"message\":\"You have exceeded a secondary rate limit\"}".utf8),
                headers: ["Retry-After": "60"]),
            for: GitHubRepoCreator.reposEndpoint)
        let error = await createExpectingError(stub)
        guard case .rateLimited? = error else {
            Issue.record("expected .rateLimited, got \(String(describing: error))")
            return
        }
    }

    @Test("A 401 maps to unauthorized")
    func unauthorized() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 401, body: Data()), for: GitHubRepoCreator.reposEndpoint)
        await #expect(throws: GitHubRepoCreatorError.unauthorized) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("A 500 maps to serverError")
    func serverError() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 500, body: Data()), for: GitHubRepoCreator.reposEndpoint)
        await #expect(throws: GitHubRepoCreatorError.serverError(500)) {
            try await makeCreator(stub).createRepo(name: "hello", isPrivate: true, token: "ghp_x")
        }
    }

    @Test("Malformed JSON on 201 surfaces unparseable")
    func unparseableBody() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Data("not json".utf8)), for: GitHubRepoCreator.reposEndpoint)
        let error = await createExpectingError(stub)
        guard case .unparseable? = error else {
            Issue.record("expected .unparseable, got \(String(describing: error))")
            return
        }
    }

    @Test("A 201 without clone_url surfaces unparseable")
    func missingCloneURL() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(status: 201, body: Data("{\"full_name\":\"octocat/hello\"}".utf8)),
            for: GitHubRepoCreator.reposEndpoint)
        let error = await createExpectingError(stub)
        guard case .unparseable? = error else {
            Issue.record("expected .unparseable, got \(String(describing: error))")
            return
        }
    }

    @Test("Transport failures surface as .transport")
    func transportFailure() async {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.failure(URLError(.notConnectedToInternet)), for: GitHubRepoCreator.reposEndpoint)
        let error = await createExpectingError(stub)
        guard case .transport? = error else {
            Issue.record("expected .transport, got \(String(describing: error))")
            return
        }
    }

    @Test("parseMessage falls back to the top-level message when errors are absent")
    func parseMessageFallback() {
        #expect(GitHubRepoCreator.parseMessage(Data("{\"message\":\"Nope\"}".utf8)) == "Nope")
        #expect(GitHubRepoCreator.parseMessage(Data("garbage".utf8)) == nil)
    }
}
