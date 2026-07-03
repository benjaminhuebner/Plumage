import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("AccountsSettingsModel")
struct AccountsSettingsModelTests {
    private struct Harness {
        let model: AccountsSettingsModel
        let storeURL: URL
        let credentials: MockGitHubCredentialStore
        let http: StubHTTPFetcher
    }

    private static let userJSON = Data(
        """
        {"login":"octocat","id":583231,"name":"The Octocat",
         "avatar_url":"https://avatars.githubusercontent.com/u/583231?v=4"}
        """.utf8)

    private func makeHarness() -> Harness {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "accounts-\(UUID().uuidString).json")
        let credentials = MockGitHubCredentialStore()
        let http = StubHTTPFetcher()
        let model = AccountsSettingsModel(
            store: GitHubAccountStore(storeURL: url),
            credentialStore: credentials,
            verifier: GitHubTokenVerifier(fetcher: http))
        return Harness(model: model, storeURL: url, credentials: credentials, http: http)
    }

    private func stubSuccess(_ http: StubHTTPFetcher, scopes: String? = nil) {
        var headers: [String: String] = [:]
        if let scopes { headers["x-oauth-scopes"] = scopes }
        http.setOutcome(
            .response(status: 200, body: Self.userJSON, headers: headers),
            for: GitHubTokenVerifier.userEndpoint)
    }

    @Test("A valid token adds the account, stores the token, and persists metadata")
    func addSuccess() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http, scopes: "repo")
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_valid"
        await harness.model.addAccount()

        #expect(harness.model.accounts.map(\.login) == ["octocat"])
        #expect(harness.model.accounts.first?.scopes == ["repo"])
        #expect(harness.credentials.storedToken(login: "octocat", host: "github.com") == "ghp_valid")
        #expect(harness.model.isAddingAccount == false)
        #expect(harness.model.draftToken.isEmpty)
        #expect(harness.model.addError == nil)

        let reloaded = GitHubAccountStore(storeURL: harness.storeURL).load()
        #expect(reloaded.map(\.login) == ["octocat"])
    }

    @Test("An invalid token surfaces an inline error and saves nothing")
    func addUnauthorized() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        harness.http.setOutcome(.response(status: 401, body: Data()), for: GitHubTokenVerifier.userEndpoint)
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_bad"
        await harness.model.addAccount()

        #expect(harness.model.accounts.isEmpty)
        #expect(harness.model.addError != nil)
        #expect(harness.model.isAddingAccount == true)
        #expect(harness.credentials.storedToken(login: "octocat", host: "github.com") == nil)
    }

    @Test("An empty token is rejected before any network call")
    func addEmptyToken() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        harness.model.beginAdd()
        harness.model.draftToken = "   "
        await harness.model.addAccount()
        #expect(harness.model.addError != nil)
        #expect(harness.http.requests.isEmpty)
    }

    @Test("A keychain save failure surfaces an error and persists no metadata")
    func addKeychainFailure() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http)
        harness.credentials.failSaves(with: GitHubCredentialStoreError.unexpectedStatus(-25308))
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_valid"
        await harness.model.addAccount()
        #expect(harness.model.addError != nil)
        #expect(harness.model.accounts.isEmpty)
        #expect(GitHubAccountStore(storeURL: harness.storeURL).load().isEmpty)
    }

    @Test("Re-adding the same login replaces the token without duplicating")
    func reAddReplaces() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http)
        harness.model.beginAdd()
        harness.model.draftToken = "token-1"
        await harness.model.addAccount()
        harness.model.beginAdd()
        harness.model.draftToken = "token-2"
        await harness.model.addAccount()

        #expect(harness.model.accounts.count == 1)
        #expect(harness.credentials.storedToken(login: "octocat", host: "github.com") == "token-2")
    }

    @Test("Remove deletes both the keychain token and the metadata")
    func removeDeletesBoth() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http)
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_valid"
        await harness.model.addAccount()
        let account = try #require(harness.model.accounts.first)

        harness.model.removeAccount(account)
        #expect(harness.model.accounts.isEmpty)
        #expect(harness.credentials.deletions.contains("octocat@github.com"))
        #expect(GitHubAccountStore(storeURL: harness.storeURL).load().isEmpty)
    }

    @Test("Push-scope hint fires only for a classic token missing repo")
    func missingPushScope() {
        let harness = makeHarness()
        func account(_ scopes: [String]) -> GitHubAccount {
            GitHubAccount(
                login: "x", host: "github.com", name: nil, avatarURL: nil,
                scopes: scopes, addedAt: Date(timeIntervalSince1970: 0))
        }
        #expect(harness.model.missingPushScope(for: account(["read:org"])) == true)
        #expect(harness.model.missingPushScope(for: account(["repo"])) == false)
        #expect(harness.model.missingPushScope(for: account([])) == false)
    }

    @Test("Reload reflects accounts written to the store")
    func reloadReadsStore() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        try GitHubAccountStore(storeURL: harness.storeURL).save([
            GitHubAccount(
                login: "hubot", host: "github.com", name: nil, avatarURL: nil,
                scopes: [], addedAt: Date(timeIntervalSince1970: 1))
        ])
        harness.model.reload()
        #expect(harness.model.accounts.map(\.login) == ["hubot"])
        #expect(harness.model.selectedAccountID == "hubot@github.com")
    }

    private static let deviceCodeJSON = Data(
        #"{"device_code":"dc","user_code":"WXYZ-1234","verification_uri":"https://github.com/login/device","interval":5}"#
            .utf8)

    private func makeOAuthModel(_ http: StubHTTPFetcher, storeURL: URL) -> AccountsSettingsModel {
        AccountsSettingsModel(
            store: GitHubAccountStore(storeURL: storeURL),
            credentialStore: MockGitHubCredentialStore(),
            verifier: GitHubTokenVerifier(fetcher: http),
            deviceFlow: GitHubDeviceFlowClient(fetcher: http, clientID: "test-client", sleep: { _ in }))
    }

    @Test("Sign in with GitHub runs the device flow, verifies, and adds the account")
    func signInWithGitHubHappyPath() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "accounts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let http = StubHTTPFetcher()
        http.setOutcome(.response(status: 200, body: Self.deviceCodeJSON), for: GitHubDeviceFlowClient.deviceCodeURL)
        http.setOutcome(
            .response(status: 200, body: Data(#"{"access_token":"gho_live"}"#.utf8)),
            for: GitHubDeviceFlowClient.tokenURL)
        http.setOutcome(
            .response(status: 200, body: Self.userJSON, headers: ["x-oauth-scopes": "repo"]),
            for: GitHubTokenVerifier.userEndpoint)
        let model = makeOAuthModel(http, storeURL: url)

        #expect(model.isOAuthConfigured)
        await model.signInWithGitHub()

        #expect(model.accounts.map(\.login) == ["octocat"])
        #expect(model.addError == nil)
        #expect(model.deviceCode == nil)
        #expect(model.isSigningIn == false)
        #expect(GitHubAccountStore(storeURL: url).load().map(\.login) == ["octocat"])
    }

    @Test("Sign in surfaces access-denied and saves nothing")
    func signInDenied() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "accounts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let http = StubHTTPFetcher()
        http.setOutcome(.response(status: 200, body: Self.deviceCodeJSON), for: GitHubDeviceFlowClient.deviceCodeURL)
        http.setOutcome(
            .response(status: 200, body: Data(#"{"error":"access_denied"}"#.utf8)),
            for: GitHubDeviceFlowClient.tokenURL)
        let model = makeOAuthModel(http, storeURL: url)

        await model.signInWithGitHub()
        #expect(model.addError != nil)
        #expect(model.accounts.isEmpty)
    }

    @Test("Sign in is unavailable when no client ID is configured")
    func signInNotConfigured() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "accounts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AccountsSettingsModel(
            store: GitHubAccountStore(storeURL: url),
            credentialStore: MockGitHubCredentialStore(),
            verifier: GitHubTokenVerifier(fetcher: StubHTTPFetcher()),
            deviceFlow: GitHubDeviceFlowClient(fetcher: StubHTTPFetcher(), clientID: "", sleep: { _ in }))

        #expect(model.isOAuthConfigured == false)
        await model.signInWithGitHub()
        #expect(model.addError != nil)
        #expect(model.accounts.isEmpty)
    }

    @Test("Sign in publishes the device code (user code + URL) before completing")
    func signInPublishesDeviceCode() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "accounts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let http = StubHTTPFetcher()
        http.setOutcome(.response(status: 200, body: Self.deviceCodeJSON), for: GitHubDeviceFlowClient.deviceCodeURL)
        http.setOutcome(
            .response(status: 200, body: Data(#"{"access_token":"gho_live"}"#.utf8)),
            for: GitHubDeviceFlowClient.tokenURL)
        // The injected sleep parks the poll before the first token request, so
        // the published deviceCode stays observable for the assertions below.
        let model = AccountsSettingsModel(
            store: GitHubAccountStore(storeURL: url),
            credentialStore: MockGitHubCredentialStore(),
            verifier: GitHubTokenVerifier(fetcher: http),
            deviceFlow: GitHubDeviceFlowClient(
                fetcher: http, clientID: "test-client",
                sleep: { _ in try await Task.sleep(for: .seconds(3600)) }))

        let task = Task { await model.signInWithGitHub() }
        try await waitUntil(timeout: .seconds(2)) { await model.deviceCode != nil }

        #expect(model.deviceCode?.userCode == "WXYZ-1234")
        #expect(model.deviceCode?.verificationURL == URL(string: "https://github.com/login/device"))
        #expect(model.isSigningIn)

        task.cancel()
        await task.value
        #expect(model.deviceCode == nil)
        #expect(model.accounts.isEmpty)
    }

    @Test("A cancelled manual add persists neither the token nor the account")
    func cancelledAddPersistsNothing() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http, scopes: "repo")
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_valid"

        let model = harness.model
        let task = Task { await model.addAccount() }
        task.cancel()
        await task.value

        #expect(harness.model.accounts.isEmpty)
        #expect(harness.credentials.storedToken(login: "octocat", host: "github.com") == nil)
        #expect(GitHubAccountStore(storeURL: harness.storeURL).load().isEmpty)
    }

    @Test("A metadata-save failure rolls back the just-saved keychain token")
    func addRollsBackTokenOnStoreFailure() async {
        let credentials = MockGitHubCredentialStore()
        let http = StubHTTPFetcher()
        stubSuccess(http)
        // Parent path is a character device, so createDirectory + write throw.
        let badURL = URL(fileURLWithPath: "/dev/null/plumage-nope/accounts.json")
        let model = AccountsSettingsModel(
            store: GitHubAccountStore(storeURL: badURL),
            credentialStore: credentials,
            verifier: GitHubTokenVerifier(fetcher: http))
        model.beginAdd()
        model.draftToken = "ghp_valid"
        await model.addAccount()

        #expect(model.addError != nil)
        #expect(model.accounts.isEmpty)
        #expect(credentials.storedToken(login: "octocat", host: "github.com") == nil)
    }

    @Test("A keychain delete failure still removes the account and surfaces an error")
    func removeSurfacesDeleteFailure() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.storeURL) }
        stubSuccess(harness.http)
        harness.model.beginAdd()
        harness.model.draftToken = "ghp_valid"
        await harness.model.addAccount()
        let account = try #require(harness.model.accounts.first)

        harness.credentials.failDeletes(with: GitHubCredentialStoreError.unexpectedStatus(-25308))
        harness.model.removeAccount(account)

        #expect(harness.model.accounts.isEmpty)
        #expect(harness.model.removeError != nil)
        #expect(GitHubAccountStore(storeURL: harness.storeURL).load().isEmpty)
    }
}
