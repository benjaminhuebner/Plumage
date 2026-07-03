import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("GitSyncModel")
struct GitSyncModelTests {
    private let repoURL = URL(filePath: "/tmp/probe-repo")

    // Hermetic model: the resolution deps resolve to "no account" (empty remote,
    // empty store, mock keychain) so credential resolution never touches real
    // git, disk, or the keychain.
    private func makeModel(
        runner: any GitSyncing,
        branch: String = "main",
        autoDismiss: Double = 1.0,
        operation: GitSyncOperation = .push,
        remoteLister: GitRemoteLister = GitRemoteLister(
            runner: MockGitProcessRunner(), resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") })
    ) -> GitSyncModel {
        GitSyncModel(
            repoURL: repoURL,
            operation: operation,
            currentBranch: branch,
            runner: runner,
            remoteRunner: GitRemoteURLRunner(
                runner: MockGitProcessRunner(), resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") }),
            remoteLister: remoteLister,
            accountStore: GitHubAccountStore(
                storeURL: FileManager.default.temporaryDirectory
                    .appending(path: "gh-\(UUID().uuidString).json")),
            credentialStore: MockGitHubCredentialStore(),
            successAutoDismissSeconds: autoDismiss)
    }

    @Test("happy push streams lines then transitions to finished(exit: 0)")
    func happyPush() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "Enumerating objects: 5")),
            .line(GitStreamLine(source: .stdout, text: "To github.com:foo/bar.git")),
            .finished(exitCode: 0),
        ])
        let model = makeModel(runner: runner, autoDismiss: 0.01)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(model.lines.count == 2)
        #expect(model.shouldAutoDismiss)
        #expect(model.didFail == false)
    }

    @Test("a push model opens in the configuring state; pull runs immediately")
    func pushOpensConfiguring() {
        let push = makeModel(runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]))
        #expect(push.isConfiguring)
        let pull = makeModel(
            runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]), operation: .pull)
        #expect(!pull.isConfiguring)
    }

    @Test("loadRemotes lists remotes and defaults the selection to origin")
    func loadRemotesDefaultsOrigin() async {
        let git = MockGitProcessRunner()
        git.stdoutForArgs[["-C", repoURL.path, "remote"]] = "upstream\norigin\nfork\n"
        let lister = GitRemoteLister(
            runner: git, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") })
        let model = makeModel(
            runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]), remoteLister: lister)
        await model.loadRemotes()
        #expect(model.availableRemotes == ["upstream", "origin", "fork"])
        #expect(model.pushRemote == "origin")
    }

    @Test("loadRemotes keeps a still-valid non-origin selection instead of resetting")
    func loadRemotesKeepsSelection() async {
        let git = MockGitProcessRunner()
        git.stdoutForArgs[["-C", repoURL.path, "remote"]] = "origin\nupstream\n"
        let lister = GitRemoteLister(
            runner: git, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") })
        let model = makeModel(
            runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]), remoteLister: lister)
        model.pushRemote = "upstream"
        await model.loadRemotes()
        #expect(model.pushRemote == "upstream")
    }

    @Test("loadRemotes swallows a lister failure and leaves no remotes")
    func loadRemotesSwallowsError() async {
        let git = MockGitProcessRunner()
        git.exitCodeForArgs[["-C", repoURL.path, "remote"]] = 128
        let lister = GitRemoteLister(
            runner: git, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") })
        let model = makeModel(
            runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]), remoteLister: lister)
        await model.loadRemotes()
        #expect(model.availableRemotes.isEmpty)
        #expect(!model.isLoadingRemotes)
    }

    @Test("loadRemotes falls back to the first remote when there is no origin")
    func loadRemotesNoOrigin() async {
        let git = MockGitProcessRunner()
        git.stdoutForArgs[["-C", repoURL.path, "remote"]] = "fork\nupstream\n"
        let lister = GitRemoteLister(
            runner: git, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") })
        let model = makeModel(
            runner: ScriptedSyncRunner(script: [.finished(exitCode: 0)]), remoteLister: lister)
        await model.loadRemotes()
        #expect(model.pushRemote == "fork")
    }

    @Test("start passes the chosen push options through to the runner")
    func startPassesOptions() async throws {
        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = makeModel(runner: runner, autoDismiss: 0.01)
        model.pushRemote = "fork"
        model.includeTags = true
        model.forcePush = true
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)
        #expect(
            runner.receivedPushOptions
                == GitPushOptions(remote: "fork", includeTags: true, force: true))
    }

    @Test("credential resolution follows the picked remote, not origin")
    func credentialFollowsPickedRemote() async throws {
        let accountsURL = FileManager.default.temporaryDirectory
            .appending(path: "gh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([
            GitHubAccount(
                login: "octocat", host: "github.com", name: nil, avatarURL: nil,
                scopes: ["repo"], addedAt: Date(timeIntervalSince1970: 1))
        ])
        let gitMock = MockGitProcessRunner()
        gitMock.stdoutForArgs[["-C", repoURL.path, "remote", "get-url", "fork"]] =
            "https://github.com/octocat/Hello.git\n"
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live_token", login: "octocat", host: "github.com")
        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner,
            remoteRunner: GitRemoteURLRunner(
                runner: gitMock, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") }),
            accountStore: GitHubAccountStore(storeURL: accountsURL),
            credentialStore: credentials,
            successAutoDismissSeconds: 0.01)
        model.pushRemote = "fork"
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(gitMock.recordedCalls.contains(["-C", repoURL.path, "remote", "get-url", "fork"]))
        #expect(runner.receivedCredential == GitPushCredential(login: "octocat", token: "ghp_live_token"))
    }

    @Test("failure surfaces exit code and keeps sheet open")
    func failureKeepsOpen() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "error: failed to push some refs")),
            .finished(exitCode: 1),
        ])
        let model = makeModel(runner: runner)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(model.didFail)
        #expect(!model.shouldAutoDismiss)
    }

    @Test("auth-prompt flips state to authBlocked and ignores subsequent .finished")
    func authBlockedSticks() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "Username for 'https://github.com':")),
            .authPromptDetected,
            .finished(exitCode: 128),
        ])
        let model = makeModel(runner: runner)
        model.start()
        await runner.complete()
        try await waitFor(timeout: .seconds(2)) { await model.isAuthBlocked }
        #expect(model.isAuthBlocked)
        #expect(!model.shouldAutoDismiss)
    }

    @Test("retryingWithUpstream marker propagates to model flag")
    func retryFlag() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "no upstream")),
            .retryingWithUpstream(branch: "feature/x"),
            .line(GitStreamLine(source: .stdout, text: "Branch 'feature/x' set up to track 'origin/feature/x'.")),
            .finished(exitCode: 0),
        ])
        let model = makeModel(runner: runner, branch: "feature/x", autoDismiss: 0.01)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)
        #expect(model.didRetryWithUpstream)
    }

    @Test("a rejected credential surfaces the login and keeps the sheet open")
    func credentialRejectedSurfaces() async throws {
        let runner = ScriptedSyncRunner(script: [
            .line(GitStreamLine(source: .stderr, text: "fatal: Authentication failed")),
            .credentialRejected(login: "octocat"),
            .finished(exitCode: 128),
        ])
        let model = makeModel(runner: runner)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)
        #expect(model.credentialRejectedLogin == "octocat")
        #expect(model.didFail)
        #expect(!model.shouldAutoDismiss)
    }

    @Test("resolves the account for the repo and passes its token to the runner")
    func resolvesCredential() async throws {
        let accountsURL = FileManager.default.temporaryDirectory
            .appending(path: "gh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        try GitHubAccountStore(storeURL: accountsURL).save([
            GitHubAccount(
                login: "octocat", host: "github.com", name: nil, avatarURL: nil,
                scopes: ["repo"], addedAt: Date(timeIntervalSince1970: 1))
        ])
        let gitMock = MockGitProcessRunner()
        gitMock.stdoutForArgs[["-C", repoURL.path, "remote", "get-url", "origin"]] =
            "https://github.com/octocat/Hello.git\n"
        let credentials = MockGitHubCredentialStore()
        credentials.preset("ghp_live_token", login: "octocat", host: "github.com")

        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner,
            remoteRunner: GitRemoteURLRunner(
                runner: gitMock, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") }),
            accountStore: GitHubAccountStore(storeURL: accountsURL),
            credentialStore: credentials,
            successAutoDismissSeconds: 0.01)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(runner.receivedCredential == GitPushCredential(login: "octocat", token: "ghp_live_token"))
        #expect(model.usingAccountLogin == "octocat")
    }

    // A resolved account with a missing/empty/unreadable token must yield nil,
    // handing control to the auth-blocked path instead of pushing a bogus one.
    private func modelWithAccount(
        credentials: MockGitHubCredentialStore,
        runner: ScriptedSyncRunner,
        accountsURL: URL
    ) throws -> GitSyncModel {
        try GitHubAccountStore(storeURL: accountsURL).save([
            GitHubAccount(
                login: "octocat", host: "github.com", name: nil, avatarURL: nil,
                scopes: ["repo"], addedAt: Date(timeIntervalSince1970: 1))
        ])
        let gitMock = MockGitProcessRunner()
        gitMock.stdoutForArgs[["-C", repoURL.path, "remote", "get-url", "origin"]] =
            "https://github.com/octocat/Hello.git\n"
        return GitSyncModel(
            repoURL: repoURL,
            operation: .push,
            currentBranch: "main",
            runner: runner,
            remoteRunner: GitRemoteURLRunner(
                runner: gitMock, resolveBinary: { URL(fileURLWithPath: "/usr/bin/git") }),
            accountStore: GitHubAccountStore(storeURL: accountsURL),
            credentialStore: credentials,
            successAutoDismissSeconds: 0.01)
    }

    @Test("an account with no readable token resolves to no credential")
    func fallbackNoToken() async throws {
        let accountsURL = FileManager.default.temporaryDirectory
            .appending(path: "gh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = try modelWithAccount(
            credentials: MockGitHubCredentialStore(), runner: runner, accountsURL: accountsURL)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(runner.receivedCredential == nil)
        #expect(model.usingAccountLogin == nil)
    }

    @Test("an account whose stored token is empty resolves to no credential")
    func fallbackEmptyToken() async throws {
        let accountsURL = FileManager.default.temporaryDirectory
            .appending(path: "gh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        let credentials = MockGitHubCredentialStore()
        credentials.preset("", login: "octocat", host: "github.com")
        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = try modelWithAccount(
            credentials: credentials, runner: runner, accountsURL: accountsURL)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(runner.receivedCredential == nil)
        #expect(model.usingAccountLogin == nil)
    }

    @Test("a keychain read error resolves to no credential")
    func fallbackReadThrows() async throws {
        let accountsURL = FileManager.default.temporaryDirectory
            .appending(path: "gh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: accountsURL) }
        let credentials = MockGitHubCredentialStore()
        credentials.failReads(with: GitHubCredentialStoreError.unexpectedStatus(-25308))
        let runner = ScriptedSyncRunner(script: [.finished(exitCode: 0)])
        let model = try modelWithAccount(
            credentials: credentials, runner: runner, accountsURL: accountsURL)
        model.start()
        await runner.complete()
        try await waitForFinished(model: model)

        #expect(runner.receivedCredential == nil)
        #expect(model.usingAccountLogin == nil)
    }
}

// MARK: - Helpers

private func waitForFinished(model: GitSyncModel) async throws {
    try await waitFor(timeout: .seconds(2)) {
        await MainActor.run { !model.isRunning }
    }
}

private func waitFor(
    timeout: Duration,
    _ condition: @Sendable () async -> Bool
) async throws {
    do {
        try await waitUntil(timeout: timeout, condition: condition)
    } catch {
        Issue.record("condition not satisfied in time")
        // Rethrow: swallowing the timeout let follow-up assertions fire
        // against a state the test never reached.
        throw error
    }
}

// Test runner that emits a scripted sequence on demand. `complete()` waits
// for the consumer task to finish so assertions see the full state.
private final class ScriptedSyncRunner: GitSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private let script: [GitSyncEvent]
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var _receivedCredential: GitPushCredential?
    private var _receivedPushOptions: GitPushOptions?

    init(script: [GitSyncEvent]) {
        self.script = script
    }

    var receivedCredential: GitPushCredential? {
        lock.lock()
        defer { lock.unlock() }
        return _receivedCredential
    }

    var receivedPushOptions: GitPushOptions? {
        lock.lock()
        defer { lock.unlock() }
        return _receivedPushOptions
    }

    func run(
        operation: GitSyncOperation,
        repoURL: URL,
        currentBranch: String?,
        credential: GitPushCredential?,
        pushOptions: GitPushOptions
    ) -> AsyncStream<GitSyncEvent> {
        lock.lock()
        _receivedCredential = credential
        _receivedPushOptions = pushOptions
        lock.unlock()
        return AsyncStream { continuation in
            for event in script { continuation.yield(event) }
            continuation.finish()
            DispatchQueue.global().async { [self] in
                lock.lock()
                let cont = completionContinuation
                completionContinuation = nil
                lock.unlock()
                cont?.resume()
            }
        }
    }

    func complete() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            completionContinuation = cont
            lock.unlock()
        }
        // Callers follow with a waitFor/waitForFinished poll that converges on
        // the model's final state, so no fixed settle is needed here.
    }
}
