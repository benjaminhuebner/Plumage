import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("AddRemoteModel")
struct AddRemoteModelTests {
    private let repoURL = URL(fileURLWithPath: "/tmp/repo")
    private let fakeGit = URL(fileURLWithPath: "/usr/bin/git")
    private static let cloneURL = "https://github.com/octocat/hello.git"
    private static let createdJSON = Data(
        """
        {"full_name":"octocat/hello","clone_url":"https://github.com/octocat/hello.git"}
        """.utf8)

    // MARK: helpers

    private func tempAccountsURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "gh-\(UUID().uuidString).json")
    }

    private func account(_ login: String, addedAt: TimeInterval) -> GitHubAccount {
        GitHubAccount(
            login: login, host: "github.com", name: nil, avatarURL: nil,
            scopes: ["repo"], addedAt: Date(timeIntervalSince1970: addedAt))
    }

    private func gitMock(existingRemotes: String = "") -> MockGitProcessRunner {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs[["-C", repoURL.path, "remote"]] = existingRemotes
        return mock
    }

    private func makeModel(
        git: MockGitProcessRunner,
        accountsURL: URL,
        stub: StubHTTPFetcher = StubHTTPFetcher(),
        credentials: MockGitHubCredentialStore = MockGitHubCredentialStore()
    ) -> AddRemoteModel {
        AddRemoteModel(
            repoURL: repoURL,
            runner: GitRemoteAddRunner(runner: git, resolveBinary: { self.fakeGit }),
            creator: GitHubRepoCreator(fetcher: stub, endpoint: GitHubRepoCreator.reposEndpoint),
            remoteLister: GitRemoteLister(runner: git, resolveBinary: { self.fakeGit }),
            accountStore: GitHubAccountStore(storeURL: accountsURL),
            credentialStore: credentials)
    }

    private func addArgs(name: String, url: String) -> [String] {
        ["-C", repoURL.path, "remote", "add", name, url]
    }

    // MARK: validation

    @Test("remoteNameError catches empty, unsafe, and duplicate names")
    func remoteNameErrorCases() {
        #expect(AddRemoteModel.remoteNameError("", existing: []) != nil)
        #expect(AddRemoteModel.remoteNameError("   ", existing: []) != nil)
        #expect(AddRemoteModel.remoteNameError("-x", existing: []) != nil)
        #expect(AddRemoteModel.remoteNameError("origin", existing: ["origin"]) != nil)
        #expect(AddRemoteModel.remoteNameError("upstream", existing: ["origin"]) == nil)
    }

    @Test("existing mode requires a non-empty URL")
    func existingModeURLRequired() {
        let model = makeModel(git: gitMock(), accountsURL: tempAccountsURL())
        model.mode = .existing
        #expect(model.validationHint != nil)
        model.existingURL = "https://github.com/o/r.git"
        #expect(model.validationHint == nil)
        #expect(model.canSubmit)
    }

    @Test("a name colliding with an existing remote blocks Add")
    func uniquenessBlocksAdd() async throws {
        let model = makeModel(git: gitMock(existingRemotes: "origin\n"), accountsURL: tempAccountsURL())
        await model.load()
        model.existingURL = "https://github.com/o/r.git"
        model.existingName = "origin"
        #expect(model.validationHint?.contains("already exists") == true)
        model.existingName = "upstream"
        #expect(model.validationHint == nil)
    }

    @Test("New on GitHub is blocked without an account")
    func newModeNeedsAccount() async {
        let model = makeModel(git: gitMock(), accountsURL: tempAccountsURL())
        await model.load()
        model.mode = .newOnGitHub
        #expect(model.hasAccounts == false)
        #expect(model.validationHint?.contains("Settings") == true)
    }

    @Test("New on GitHub requires a repository name")
    func newModeNeedsRepoName() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let model = makeModel(git: gitMock(), accountsURL: accountsURL)
        await model.load()
        model.mode = .newOnGitHub
        #expect(model.validationHint == nil)
        model.newRepoName = "  "
        #expect(model.validationHint?.contains("repository name") == true)
    }

    // MARK: accounts

    @Test("the default selected account is the most recently added")
    func defaultAccountIsMostRecent() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([
            account("older", addedAt: 1), account("newer", addedAt: 2),
        ])
        let model = makeModel(git: gitMock(), accountsURL: accountsURL)
        await model.load()
        #expect(model.showsAccountPicker)
        #expect(model.selectedAccount?.login == "newer")
    }

    @Test("the token sent to the API is the explicitly selected account's, not the default")
    func submitNewUsesSelectedAccountToken() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([
            account("octocat", addedAt: 1), account("hubber", addedAt: 2),
        ])
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_octocat", login: "octocat", host: "github.com")
        credentials.preset("ghp_hubber", login: "hubber", host: "github.com")
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        let model = makeModel(git: gitMock(), accountsURL: accountsURL, stub: stub, credentials: credentials)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        // Default would be the most recent (hubber); pick the older one explicitly.
        model.selectedAccountID = "octocat@github.com"
        await model.submit()

        #expect(model.didFinish)
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_octocat")
    }

    @Test("load() resets a stale selected-account id to the most recent")
    func loadResetsStaleSelection() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([
            account("octocat", addedAt: 1), account("newer", addedAt: 2),
        ])
        let model = makeModel(git: gitMock(), accountsURL: accountsURL)
        model.selectedAccountID = "ghost@github.com"
        await model.load()
        #expect(model.selectedAccountID == "newer@github.com")
    }

    @Test("the repo name defaults to the repository folder name")
    func repoNameDefaultsToFolder() {
        let model = makeModel(git: gitMock(), accountsURL: tempAccountsURL())
        #expect(model.newRepoName == "repo")
    }

    // MARK: existing-mode submit

    @Test("submitting existing mode runs `git remote add` and finishes")
    func submitExisting() async {
        let git = gitMock()
        let model = makeModel(git: git, accountsURL: tempAccountsURL())
        model.existingName = "origin"
        model.existingURL = "https://github.com/o/r.git"
        await model.submit()
        #expect(git.recordedCalls.contains(addArgs(name: "origin", url: "https://github.com/o/r.git")))
        #expect(model.didFinish)
        #expect(model.error == nil)
    }

    @Test("a failing git remote add surfaces an inline error and does not finish")
    func submitExistingGitFails() async {
        let git = gitMock()
        let args = addArgs(name: "origin", url: "https://github.com/o/r.git")
        git.exitCodeForArgs[args] = 3
        git.stderrForArgs[args] = "error: remote origin already exists."
        let model = makeModel(git: git, accountsURL: tempAccountsURL())
        model.existingURL = "https://github.com/o/r.git"
        await model.submit()
        #expect(model.didFinish == false)
        #expect(model.error != nil)
    }

    // MARK: new-on-GitHub submit

    @Test("submitting New on GitHub creates the repo then wires the HTTPS remote")
    func submitNewOnGitHub() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live", login: "octocat", host: "github.com")
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        let git = gitMock()
        let model = makeModel(git: git, accountsURL: accountsURL, stub: stub, credentials: credentials)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        await model.submit()

        let createRequest = try #require(stub.requests.first)
        let body = try #require(createRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "hello")
        #expect(json["private"] as? Bool == true)
        #expect(git.recordedCalls.contains(addArgs(name: "origin", url: Self.cloneURL)))
        #expect(model.didFinish)
        #expect(model.error == nil)
    }

    @Test("a 422 from the API blocks the remote wiring and shows the message")
    func submitNewNameTaken() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live", login: "octocat", host: "github.com")
        let stub = StubHTTPFetcher()
        stub.setOutcome(
            .response(status: 422, body: Data("{\"message\":\"name already exists\"}".utf8)),
            for: GitHubRepoCreator.reposEndpoint)
        let git = gitMock()
        let model = makeModel(git: git, accountsURL: accountsURL, stub: stub, credentials: credentials)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        await model.submit()

        #expect(model.didFinish == false)
        #expect(model.error != nil)
        #expect(git.recordedCalls.contains { $0.contains("add") } == false)
    }

    @Test("API success but a failing git wiring names both facts in the error")
    func submitNewWiringFails() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live", login: "octocat", host: "github.com")
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        let git = gitMock()
        let args = addArgs(name: "origin", url: Self.cloneURL)
        git.exitCodeForArgs[args] = 3
        git.stderrForArgs[args] = "error: remote origin already exists."
        let model = makeModel(git: git, accountsURL: accountsURL, stub: stub, credentials: credentials)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        await model.submit()

        #expect(model.didFinish == false)
        #expect(model.error?.contains("Created") == true)
        #expect(model.error?.contains("wiring the local remote failed") == true)
    }

    @Test("New on GitHub with no readable token errors before calling the API")
    func submitNewNoToken() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let stub = StubHTTPFetcher()
        let git = gitMock()
        let model = makeModel(git: git, accountsURL: accountsURL, stub: stub)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        await model.submit()

        #expect(model.didFinish == false)
        #expect(model.error?.contains("token") == true)
        #expect(stub.requests.isEmpty)
    }

    @Test("after a wiring failure, retrying re-wires the created repo without a second POST")
    func submitNewRetryWiresWithoutRecreate() async throws {
        let accountsURL = tempAccountsURL()
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([account("octocat", addedAt: 1)])
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live", login: "octocat", host: "github.com")
        let stub = StubHTTPFetcher()
        stub.setOutcome(.response(status: 201, body: Self.createdJSON), for: GitHubRepoCreator.reposEndpoint)
        let git = gitMock()
        let args = addArgs(name: "origin", url: Self.cloneURL)
        git.exitCodeForArgs[args] = 3
        git.stderrForArgs[args] = "error: remote origin already exists."
        let model = makeModel(git: git, accountsURL: accountsURL, stub: stub, credentials: credentials)
        await model.load()
        model.mode = .newOnGitHub
        model.newRepoName = "hello"
        await model.submit()
        #expect(model.error?.contains("Created") == true)
        #expect(model.didFinish == false)

        git.exitCodeForArgs = [:]
        await model.submit()
        #expect(model.didFinish)
        #expect(stub.requests.count == 1)
    }

    @Test("submit() ignores a re-entrant call while one is already in flight")
    func submitIsReentrancyGuarded() async {
        let gate = GatedRemoteAdder()
        let model = AddRemoteModel(
            repoURL: repoURL,
            runner: gate,
            remoteLister: GitRemoteLister(runner: gitMock(), resolveBinary: { self.fakeGit }),
            accountStore: GitHubAccountStore(storeURL: tempAccountsURL()))
        model.existingName = "origin"
        model.existingURL = "https://github.com/o/r.git"

        let first = Task { await model.submit() }
        await gate.waitForStart()
        await model.submit()
        #expect(gate.callCount == 1)
        gate.releaseNow()
        await first.value
        #expect(model.didFinish)
    }
}

// Blocks inside addRemote until the test releases it, so a re-entrant submit()
// runs while the first is provably still in flight. @unchecked Sendable: all
// state is guarded by the NSLock.
private final class GatedRemoteAdder: GitRemoteAdding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    var callCount: Int { lock.withLock { _callCount } }

    func addRemote(name: String, url: String, repoURL: URL) async throws {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            _callCount += 1
            let waiter = startWaiter
            startWaiter = nil
            return waiter
        }
        waiter?.resume()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock { release = continuation }
        }
    }

    func waitForStart() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyStarted: Bool = lock.withLock {
                if _callCount > 0 { return true }
                startWaiter = continuation
                return false
            }
            if alreadyStarted { continuation.resume() }
        }
    }

    func releaseNow() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            let continuation = release
            release = nil
            return continuation
        }
        continuation?.resume()
    }
}
