import Foundation
import Testing

@testable import Plumage

@Suite("GitHubIssuesClient")
struct GitHubIssuesClientTests {
    private func makeClient(_ stub: StubHTTPFetcher) -> GitHubIssuesClient {
        GitHubIssuesClient(fetcher: stub, apiBase: GitHubIssuesClient.apiBase)
    }

    private func firstURL(owner: String = "octocat", repo: String = "hello") throws -> URL {
        try #require(
            GitHubIssuesClient.issuesURL(owner: owner, repo: repo, base: GitHubIssuesClient.apiBase))
    }

    private func expectError(_ stub: StubHTTPFetcher) async -> GitHubIssuesClientError? {
        await #expect(throws: GitHubIssuesClientError.self) {
            try await makeClient(stub).listOpenIssues(owner: "octocat", repo: "hello", token: "ghp_x")
        }
    }

    @Test("lists open issues, maps labels[].name, tolerates null body, drops PRs")
    func listsAndFilters() async throws {
        let stub = StubHTTPFetcher()
        let body = Data(
            """
            [
              {"number": 1, "title": "First", "body": "hello",
               "html_url": "https://github.com/octocat/hello/issues/1",
               "labels": [{"name":"bug"},{"name":"v0.5"}],
               "updated_at": "2026-07-03T06:05:39Z", "user": {"login":"octocat"}},
              {"number": 2, "title": "No body", "body": null,
               "html_url": "https://github.com/octocat/hello/issues/2",
               "labels": [], "updated_at": "2026-07-03T07:00:00Z", "user": {"login":"contrib"}},
              {"number": 3, "title": "A PR", "body": "x",
               "html_url": "https://github.com/octocat/hello/pull/3",
               "pull_request": {"url": "https://api.github.com/repos/octocat/hello/pulls/3"},
               "labels": [], "updated_at": "2026-07-03T08:00:00Z"}
            ]
            """.utf8)
        stub.setOutcome(.response(status: 200, body: body), for: try firstURL())

        let issues = try await makeClient(stub).listOpenIssues(
            owner: "octocat", repo: "hello", token: "ghp_x")
        #expect(issues.map(\.number) == [1, 2])
        #expect(issues[0].id == 1)
        #expect(issues[0].labels == ["bug", "v0.5"])
        #expect(issues[0].body == "hello")
        #expect(issues[1].body == nil)
        #expect(issues[1].authorLogin == "contrib")
        #expect(issues[0].htmlURL == URL(string: "https://github.com/octocat/hello/issues/1"))
    }

    @Test("issues request carries the GitHub headers and bearer token")
    func requestShape() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Data("[]".utf8)), for: try firstURL())
        _ = try await makeClient(stub).listOpenIssues(owner: "octocat", repo: "hello", token: "ghp_x")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_x")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.url == (try firstURL()))
    }

    @Test("200 with an empty array yields no issues")
    func emptyList() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Data("[]".utf8)), for: try firstURL())
        let issues = try await makeClient(stub).listOpenIssues(
            owner: "octocat", repo: "hello", token: "ghp_x")
        #expect(issues.isEmpty)
    }

    @Test("follows the rel=next Link header across pages")
    func pagination() async throws {
        let stub = StubHTTPFetcher()
        let page2 = try #require(
            URL(string: "https://api.github.com/repositories/42/issues?state=open&per_page=100&page=2"))
        stub.setOutcome(
            .response(
                status: 200,
                body: Data(
                    """
                    [{"number":1,"title":"a","html_url":"https://github.com/o/r/issues/1","labels":[],"updated_at":"2026-07-03T06:05:39Z"}]
                    """.utf8),
                headers: [
                    "Link":
                        "<\(page2.absoluteString)>; rel=\"next\", <\(page2.absoluteString)>; rel=\"last\""
                ]),
            for: try firstURL())
        stub.setOutcome(
            .response(
                status: 200,
                body: Data(
                    """
                    [{"number":2,"title":"b","html_url":"https://github.com/o/r/issues/2","labels":[],"updated_at":"2026-07-03T06:05:39Z"}]
                    """.utf8)),
            for: page2)

        let issues = try await makeClient(stub).listOpenIssues(
            owner: "octocat", repo: "hello", token: "ghp_x")
        #expect(issues.map(\.number) == [1, 2])
    }

    @Test("301 follows the Location header to the renamed repo")
    func followsRedirect() async throws {
        let stub = StubHTTPFetcher()
        let moved = try #require(
            URL(string: "https://api.github.com/repositories/99/issues?state=open&per_page=100"))
        stub.setOutcome(
            .response(status: 301, body: Data(), headers: ["Location": moved.absoluteString]),
            for: try firstURL())
        stub.setOutcome(
            .response(
                status: 200,
                body: Data(
                    """
                    [{"number":7,"title":"moved","html_url":"https://github.com/o/r2/issues/7","labels":[],"updated_at":"2026-07-03T06:05:39Z"}]
                    """.utf8)),
            for: moved)

        let issues = try await makeClient(stub).listOpenIssues(
            owner: "octocat", repo: "hello", token: "ghp_x")
        #expect(issues.map(\.number) == [7])
    }

    @Test("401 maps to unauthorized")
    func unauthorized() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 401, body: Data()), for: try firstURL())
        await #expect(throws: GitHubIssuesClientError.unauthorized) {
            try await makeClient(stub).listOpenIssues(owner: "octocat", repo: "hello", token: "ghp_x")
        }
    }

    @Test("404 maps to notFound")
    func notFound() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 404, body: Data()), for: try firstURL())
        await #expect(throws: GitHubIssuesClientError.notFound) {
            try await makeClient(stub).listOpenIssues(owner: "octocat", repo: "hello", token: "ghp_x")
        }
    }

    @Test("403 with rate-limit headers maps to rateLimited")
    func rateLimited() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(
                status: 403,
                body: Data("{\"message\":\"API rate limit exceeded\"}".utf8),
                headers: ["Retry-After": "60"]),
            for: try firstURL())
        let error = await expectError(stub)
        guard case .rateLimited? = error else {
            Issue.record("expected .rateLimited, got \(String(describing: error))")
            return
        }
    }

    @Test("transport failure surfaces .transport")
    func transportFailure() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.failure(URLError(.notConnectedToInternet)), for: try firstURL())
        let error = await expectError(stub)
        guard case .transport? = error else {
            Issue.record("expected .transport, got \(String(describing: error))")
            return
        }
    }

    @Test("malformed JSON surfaces .unparseable")
    func unparseable() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Data("not json".utf8)), for: try firstURL())
        let error = await expectError(stub)
        guard case .unparseable? = error else {
            Issue.record("expected .unparseable, got \(String(describing: error))")
            return
        }
    }

    @Test("nextPageURL extracts only the rel=next target")
    func nextPageURLParsing() {
        let header =
            "<https://api.github.com/x?page=2>; rel=\"next\", <https://api.github.com/x?page=9>; rel=\"last\""
        #expect(
            GitHubIssuesClient.nextPageURL(from: header) == URL(string: "https://api.github.com/x?page=2"))
        #expect(
            GitHubIssuesClient.nextPageURL(from: "<https://api.github.com/x?page=9>; rel=\"last\"") == nil)
        #expect(GitHubIssuesClient.nextPageURL(from: nil) == nil)
    }
}
