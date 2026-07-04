import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("GitHubImportModel load/refresh")
struct GitHubImportModelTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")

    private var issuesJSON: Data {
        Data(
            """
            [{"number":1,"title":"First","body":"b",
              "html_url":"https://github.com/octocat/hello/issues/1",
              "labels":[{"name":"bug"}],"updated_at":"2026-07-03T06:05:39Z",
              "user":{"login":"octocat"}}]
            """.utf8)
    }

    private func issuesURL() throws -> URL {
        try #require(
            GitHubIssuesClient.issuesURL(owner: "octocat", repo: "hello", base: GitHubIssuesClient.apiBase))
    }

    private func remoteRunner(originURL: String?) -> GitRemoteURLRunner {
        let mock = MockGitProcessRunner()
        let args = ["-C", repoURL.path, "remote", "get-url", "origin"]
        if let originURL {
            mock.stdoutForArgs[args] = originURL + "\n"
        } else {
            mock.exitCodeForArgs[args] = 1
        }
        return GitRemoteURLRunner(runner: mock, resolveBinary: { self.fakeGit })
    }

    private func accountStore(withAccount: Bool) throws -> GitHubAccountStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "gh-\(UUID().uuidString).json")
        let store = GitHubAccountStore(storeURL: url)
        if withAccount {
            try store.save([
                GitHubAccount(
                    login: "octocat", host: "github.com", name: nil, avatarURL: nil, scopes: [],
                    addedAt: Date(timeIntervalSince1970: 0))
            ])
        }
        return store
    }

    private func credentialStore(withToken: Bool) -> MockGitHubCredentialStore {
        let store = MockGitHubCredentialStore()
        if withToken { store.preset("ghp_x", login: "octocat", host: "github.com") }
        return store
    }

    private func makeModel(
        originURL: String? = "https://github.com/octocat/hello.git",
        withAccount: Bool = true, withToken: Bool = true,
        stub: StubHTTPFetcher
    ) throws -> GitHubImportModel {
        GitHubImportModel(
            projectURL: repoURL,
            boundAccountID: nil,
            remoteRunner: remoteRunner(originURL: originURL),
            accountStore: try accountStore(withAccount: withAccount),
            credentialStore: credentialStore(withToken: withToken),
            client: GitHubIssuesClient(fetcher: stub, apiBase: GitHubIssuesClient.apiBase))
    }

    @Test("load resolves origin + account and lists open issues")
    func loadHappy() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: issuesJSON), for: try issuesURL())
        let model = try makeModel(stub: stub)
        await model.load()
        guard case .loaded(let issues) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(issues.map(\.number) == [1])
        #expect(model.repoLabel == "octocat/hello")
    }

    @Test("empty issue list yields .empty")
    func loadEmpty() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: Data("[]".utf8)), for: try issuesURL())
        let model = try makeModel(stub: stub)
        await model.load()
        #expect(model.state == .empty)
    }

    @Test("no origin remote yields .unavailable")
    func noOrigin() async throws {
        let model = try makeModel(originURL: nil, stub: StubHTTPFetcher())
        await model.load()
        guard case .unavailable = model.state else {
            Issue.record("expected .unavailable, got \(model.state)")
            return
        }
    }

    @Test("non-github origin yields .unavailable")
    func nonGithub() async throws {
        let model = try makeModel(originURL: "https://gitlab.com/octocat/hello.git", stub: StubHTTPFetcher())
        await model.load()
        guard case .unavailable = model.state else {
            Issue.record("expected .unavailable, got \(model.state)")
            return
        }
    }

    @Test("github origin but no account yields .unavailable, repo still resolved")
    func noAccount() async throws {
        let model = try makeModel(withAccount: false, withToken: false, stub: StubHTTPFetcher())
        await model.load()
        guard case .unavailable = model.state else {
            Issue.record("expected .unavailable, got \(model.state)")
            return
        }
        #expect(model.repoLabel == "octocat/hello")
    }

    @Test("404 yields .failed")
    func notFoundFails() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 404, body: Data()), for: try issuesURL())
        let model = try makeModel(stub: stub)
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
    }

    @Test("rate limit yields .rateLimited")
    func rateLimited() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(
                status: 403, body: Data("{\"message\":\"rate limit\"}".utf8),
                headers: ["Retry-After": "60"]),
            for: try issuesURL())
        let model = try makeModel(stub: stub)
        await model.load()
        guard case .rateLimited = model.state else {
            Issue.record("expected .rateLimited, got \(model.state)")
            return
        }
    }

    @Test("refresh keeps the last list on a transport error")
    func refreshKeepsLast() async throws {
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 200, body: issuesJSON), for: try issuesURL())
        let model = try makeModel(stub: stub)
        await model.load()
        #expect(model.openCount == 1)

        stub.setOutcome(.failure(URLError(.notConnectedToInternet)), for: try issuesURL())
        await model.refresh()
        guard case .loaded(let issues) = model.state else {
            Issue.record("expected kept .loaded, got \(model.state)")
            return
        }
        #expect(issues.map(\.number) == [1])
    }
}
