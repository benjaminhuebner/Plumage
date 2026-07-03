import Foundation
import Observation

// Identifiable wrapper for the streaming output list: positional ForEach
// identity re-identifies every row on each appended line.
nonisolated struct NumberedStreamLine: Identifiable, Sendable, Equatable {
    let id: Int
    let line: GitStreamLine
}

@Observable
@MainActor
final class GitSyncModel {
    enum RunState: Sendable, Equatable {
        case configuring
        case idle
        case running
        case authBlocked
        case finished(exitCode: Int32)
    }

    let repoURL: URL
    let operation: GitSyncOperation
    let currentBranch: String?

    // Push-sheet options, bound two-way by the config form. Defaults match
    // GitPushOptions.default; loadRemotes() refines the remote selection.
    var pushRemote: String = GitPushOptions.default.remote
    var includeTags: Bool = GitPushOptions.default.includeTags
    var forcePush: Bool = GitPushOptions.default.force
    private(set) var availableRemotes: [String] = []
    private(set) var isLoadingRemotes = false

    private(set) var lines: [NumberedStreamLine] = []
    @ObservationIgnored private var nextLineID = 0
    private(set) var state: RunState
    private(set) var didRetryWithUpstream = false
    private(set) var usingAccountLogin: String?
    private(set) var credentialRejectedLogin: String?

    private let runner: any GitSyncing
    private let boundAccountID: String?
    private let remoteRunner: GitRemoteURLRunner
    private let remoteLister: GitRemoteLister
    private let accountStore: GitHubAccountStore
    private let credentialStore: any GitHubCredentialStoring

    @ObservationIgnored private var runTask: Task<Void, Never>?
    // Auto-dismiss delay after a successful exit; surfaced so a test can
    // verify the timing if it needs to. 1.0 s lets the user see the final
    // line + a confirmation tick before the sheet collapses.
    @ObservationIgnored let successAutoDismissSeconds: Double

    init(
        repoURL: URL,
        operation: GitSyncOperation,
        currentBranch: String?,
        runner: any GitSyncing = GitSyncRunner(),
        boundAccountID: String? = nil,
        remoteRunner: GitRemoteURLRunner = GitRemoteURLRunner(runner: ProductionGitProcessRunner()),
        remoteLister: GitRemoteLister = GitRemoteLister(),
        accountStore: GitHubAccountStore = GitHubAccountStore(),
        credentialStore: any GitHubCredentialStoring = ProductionGitHubCredentialStore(),
        successAutoDismissSeconds: Double = 1.0
    ) {
        self.repoURL = repoURL
        self.operation = operation
        self.currentBranch = currentBranch
        self.runner = runner
        self.boundAccountID = boundAccountID
        self.remoteRunner = remoteRunner
        self.remoteLister = remoteLister
        self.accountStore = accountStore
        self.credentialStore = credentialStore
        self.successAutoDismissSeconds = successAutoDismissSeconds
        // Push opens on the options form; pull starts immediately.
        self.state = operation == .push ? .configuring : .idle
    }

    // Safety net for abnormal sheet teardown (Escape / system-initiated close)
    // where the view's .onDisappear → cancel() is skipped. Otherwise an
    // in-flight push/pull keeps the runner + stream alive until it finishes.
    isolated deinit {
        runTask?.cancel()
    }

    var headerTitle: String { operation.displayName }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isConfiguring: Bool {
        if case .configuring = state { return true }
        return false
    }

    // Populates the remote picker before the push runs. Best-effort: on any
    // failure the picker just falls back to the "origin" default. Keeps the
    // user's current selection if it still exists after a reload.
    func loadRemotes() async {
        isLoadingRemotes = true
        defer { isLoadingRemotes = false }
        let remotes = (try? await remoteLister.remotes(repoURL: repoURL)) ?? []
        availableRemotes = remotes
        guard !remotes.isEmpty else { return }
        if !remotes.contains(pushRemote) {
            pushRemote = remotes.first { $0 == "origin" } ?? remotes[0]
        }
    }

    var shouldAutoDismiss: Bool {
        if case .finished(let exit) = state { return exit == 0 && !isAuthBlocked }
        return false
    }

    var isAuthBlocked: Bool {
        if case .authBlocked = state { return true }
        return false
    }

    func waitForAutoDismiss() async -> Bool {
        guard shouldAutoDismiss else { return false }
        try? await Task.sleep(for: .seconds(successAutoDismissSeconds))
        return shouldAutoDismiss
    }

    var didFail: Bool {
        if case .finished(let exit) = state { return exit != 0 }
        return false
    }

    func start() {
        guard runTask == nil else { return }  // singleton-guard for menu-spam
        state = .running
        lines.removeAll()
        let options = GitPushOptions(
            remote: pushRemote, includeTags: includeTags, force: forcePush)
        runTask = Task {
            let credential = await resolveCredential()
            let stream = runner.run(
                operation: operation, repoURL: repoURL, currentBranch: currentBranch,
                credential: credential, pushOptions: options)
            for await event in stream {
                if Task.isCancelled { break }
                consume(event)
            }
            // If the loop exited without a .finished event (cancel-mid-flight),
            // close out the state so the view doesn't get stuck on "running".
            if case .running = state { state = .finished(exitCode: -1) }
            runTask = nil
        }
    }

    // No account or no readable token → nil, so the existing auth-blocked path
    // takes over unchanged. The store + keychain reads run off the main actor.
    private func resolveCredential() async -> GitPushCredential? {
        // Follow the remote the user picked for push; pull always uses origin.
        let remoteName = operation == .push ? pushRemote : "origin"
        let remote = await remoteRunner.remoteInfo(for: repoURL, remote: remoteName)
        let accountStore = accountStore
        let credentialStore = credentialStore
        let boundAccountID = boundAccountID
        let credential = await Task.detached(priority: .userInitiated) {
            () -> GitPushCredential? in
            let accounts = accountStore.load()
            guard
                let account = GitHubAccountResolver.resolve(
                    host: remote?.host, owner: remote?.owner,
                    accounts: accounts, boundAccountID: boundAccountID)
            else { return nil }
            guard
                let token = try? credentialStore.readToken(login: account.login, host: account.host),
                !token.isEmpty
            else { return nil }
            return GitPushCredential(login: account.login, token: token)
        }.value
        usingAccountLogin = credential?.login
        return credential
    }

    func cancel() {
        runTask?.cancel()
    }

    private func consume(_ event: GitSyncEvent) {
        switch event {
        case .line(let line):
            lines.append(NumberedStreamLine(id: nextLineID, line: line))
            nextLineID += 1
        case .retryingWithUpstream:
            didRetryWithUpstream = true
        case .credentialRejected(let login):
            credentialRejectedLogin = login
        case .authPromptDetected:
            // Stay in `.authBlocked` so the sheet sticks around with the
            // explanatory banner — even if the underlying process exits with
            // a non-zero code afterward, .finished should NOT collapse the
            // sheet automatically.
            state = .authBlocked
        case .finished(let exit):
            // Auth-blocked sticks; non-auth finishes update the exit code.
            if case .authBlocked = state {
                return
            }
            state = .finished(exitCode: exit)
        }
    }
}
