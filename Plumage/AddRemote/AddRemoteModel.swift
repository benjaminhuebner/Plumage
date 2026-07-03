import Foundation
import Observation

@MainActor
@Observable
final class AddRemoteModel {
    enum Mode: Hashable, CaseIterable, Sendable {
        case existing
        case newOnGitHub
    }

    let repoURL: URL

    var mode: Mode = .existing

    var existingName: String = "origin"
    var existingURL: String = ""

    var newRepoName: String
    var newRemoteName: String = "origin"
    var isPrivate: Bool = true
    var selectedAccountID: GitHubAccount.ID?

    private(set) var accounts: [GitHubAccount] = []
    private(set) var existingRemotes: [String] = []
    private(set) var isWorking = false
    private(set) var error: String?
    private(set) var didFinish = false

    // A retry after a wiring failure re-wires this instead of creating a second
    // repo (which would 422).
    private var pendingRepo: CreatedGitHubRepo?

    private let runner: any GitRemoteAdding
    private let creator: GitHubRepoCreator
    private let remoteLister: GitRemoteLister
    private let accountStore: GitHubAccountStore
    private let credentialStore: any GitHubCredentialStoring

    init(
        repoURL: URL,
        defaultRepoName: String? = nil,
        runner: any GitRemoteAdding = GitRemoteAddRunner(),
        creator: GitHubRepoCreator = GitHubRepoCreator(),
        remoteLister: GitRemoteLister = GitRemoteLister(),
        accountStore: GitHubAccountStore = GitHubAccountStore(),
        credentialStore: any GitHubCredentialStoring = ProductionGitHubCredentialStore()
    ) {
        self.repoURL = repoURL
        self.newRepoName = defaultRepoName ?? repoURL.lastPathComponent
        self.runner = runner
        self.creator = creator
        self.remoteLister = remoteLister
        self.accountStore = accountStore
        self.credentialStore = credentialStore
    }

    var hasAccounts: Bool { !accounts.isEmpty }
    var showsAccountPicker: Bool { accounts.count > 1 }

    private var mostRecentAccount: GitHubAccount? {
        accounts.max { $0.addedAt < $1.addedAt }
    }

    var selectedAccount: GitHubAccount? {
        if let selectedAccountID, let match = accounts.first(where: { $0.id == selectedAccountID }) {
            return match
        }
        return mostRecentAccount
    }

    func load() async {
        accounts = accountStore.load()
        if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = mostRecentAccount?.id
        }
        existingRemotes = (try? await remoteLister.remotes(repoURL: repoURL)) ?? []
    }

    // Non-nil string = why Add is disabled; nil = the form is submittable.
    var validationHint: String? {
        switch mode {
        case .existing:
            if let nameError = Self.remoteNameError(existingName, existing: existingRemotes) {
                return nameError
            }
            if existingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter a remote URL."
            }
            return nil
        case .newOnGitHub:
            if !hasAccounts { return "Add a GitHub account in Settings → Accounts." }
            if newRepoName.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Enter a repository name."
            }
            return Self.remoteNameError(newRemoteName, existing: existingRemotes)
        }
    }

    var canSubmit: Bool { !isWorking && validationHint == nil }

    static func remoteNameError(_ name: String, existing: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a remote name." }
        if !GitBranchName.isSafe(trimmed) { return "That remote name isn't valid." }
        if existing.contains(trimmed) { return "A remote named \"\(trimmed)\" already exists." }
        return nil
    }

    func submit() async {
        guard !isWorking else { return }
        error = nil
        guard validationHint == nil else { return }
        isWorking = true
        defer { isWorking = false }
        switch mode {
        case .existing: await addExisting()
        case .newOnGitHub: await createAndWire()
        }
    }

    private func addExisting() async {
        do {
            try await runner.addRemote(
                name: existingName.trimmingCharacters(in: .whitespaces),
                url: existingURL, repoURL: repoURL)
            didFinish = true
        } catch is CancellationError {
        } catch {
            self.error = Self.describe(error, fallback: "Couldn't add the remote.")
        }
    }

    private func createAndWire() async {
        let repoName = newRepoName.trimmingCharacters(in: .whitespaces)
        if let created = pendingRepo {
            await wire(created, repoName: repoName)
            return
        }
        guard let account = selectedAccount else {
            error = "Select a GitHub account."
            return
        }
        guard let token = await readToken(for: account), !token.isEmpty else {
            error = "No usable token for @\(account.login). Re-add the account in Settings."
            return
        }
        let created: CreatedGitHubRepo
        do {
            created = try await creator.createRepo(name: repoName, isPrivate: isPrivate, token: token)
        } catch is CancellationError {
            return
        } catch {
            self.error = Self.describe(error, fallback: "Couldn't create the repository.")
            return
        }
        pendingRepo = created
        await wire(created, repoName: repoName)
    }

    private func wire(_ created: CreatedGitHubRepo, repoName: String) async {
        do {
            try await runner.addRemote(
                name: newRemoteName.trimmingCharacters(in: .whitespaces),
                url: created.cloneURL.absoluteString, repoURL: repoURL)
            didFinish = true
        } catch is CancellationError {
        } catch {
            self.error =
                "Created \(created.fullName ?? repoName) on GitHub, but wiring the local remote failed: "
                + Self.describe(error, fallback: "git remote add failed.")
        }
    }

    private func readToken(for account: GitHubAccount) async -> String? {
        let credentialStore = credentialStore
        return await Task.detached(priority: .userInitiated) {
            (try? credentialStore.readToken(login: account.login, host: account.host)) ?? nil
        }.value
    }

    nonisolated static func describe(_ error: any Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
