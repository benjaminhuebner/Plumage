import Foundation
import Observation

@MainActor
@Observable
final class AccountsSettingsModel {
    private(set) var accounts: [GitHubAccount] = []
    var selectedAccountID: GitHubAccount.ID?

    var isAddingAccount = false
    var draftHost: String = GitHubAccount.defaultHost
    var draftToken: String = ""
    private(set) var isVerifying = false
    private(set) var isSigningIn = false
    private(set) var deviceCode: GitHubDeviceCode?
    private(set) var addError: String?
    private(set) var removeError: String?

    private let store: GitHubAccountStore
    private let credentialStore: any GitHubCredentialStoring
    private let verifier: GitHubTokenVerifier
    private let deviceFlow: GitHubDeviceFlowClient

    var isOAuthConfigured: Bool { deviceFlow.isConfigured }

    init(
        store: GitHubAccountStore = GitHubAccountStore(),
        credentialStore: any GitHubCredentialStoring = ProductionGitHubCredentialStore(),
        verifier: GitHubTokenVerifier = GitHubTokenVerifier(),
        deviceFlow: GitHubDeviceFlowClient = GitHubDeviceFlowClient()
    ) {
        self.store = store
        self.credentialStore = credentialStore
        self.verifier = verifier
        self.deviceFlow = deviceFlow
    }

    func reload() {
        accounts = store.load()
        if let id = selectedAccountID, !accounts.contains(where: { $0.id == id }) {
            selectedAccountID = accounts.first?.id
        } else if selectedAccountID == nil {
            selectedAccountID = accounts.first?.id
        }
    }

    var selectedAccount: GitHubAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    func beginAdd() {
        resetDraft()
        isAddingAccount = true
    }

    func addAccount() async {
        let host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        addError = nil
        guard !host.isEmpty else {
            addError = "Enter a host."
            return
        }
        guard !token.isEmpty else {
            addError = "Enter a token."
            return
        }

        isVerifying = true
        defer { isVerifying = false }
        await completeSignIn(token: token, host: host)
    }

    func signInWithGitHub() async {
        addError = nil
        guard deviceFlow.isConfigured else {
            addError = "GitHub sign-in isn't configured."
            return
        }
        isSigningIn = true
        defer {
            isSigningIn = false
            deviceCode = nil
        }

        let code: GitHubDeviceCode
        do {
            code = try await deviceFlow.requestDeviceCode(scope: "repo")
        } catch is CancellationError {
            return
        } catch {
            addError = Self.describe(error, fallback: "GitHub sign-in failed.")
            return
        }
        deviceCode = code

        let token: String
        do {
            token = try await deviceFlow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
        } catch is CancellationError {
            return
        } catch {
            addError = Self.describe(error, fallback: "GitHub sign-in failed.")
            return
        }

        await completeSignIn(token: token, host: GitHubAccount.defaultHost)
    }

    // Shared by manual PAT add and Sign in with GitHub: verify → keychain → store.
    private func completeSignIn(token: String, host: String) async {
        let verified: VerifiedGitHubUser
        do {
            verified = try await verifier.verify(token: token)
        } catch is CancellationError {
            return
        } catch {
            addError = Self.describe(error, fallback: "Couldn't verify the token.")
            return
        }

        // The sheet's Cancel / dismissal cancels this Task; stop before writing
        // any persistent state so a cancelled add leaves nothing behind.
        guard !Task.isCancelled else { return }

        do {
            try credentialStore.saveToken(token, login: verified.login, host: host)
        } catch {
            addError = "Couldn't save the token to the keychain."
            return
        }

        let account = GitHubAccount(
            login: verified.login, host: host, name: verified.name,
            avatarURL: verified.avatarURL, scopes: verified.scopes, addedAt: Date())
        // Re-adding the same login@host replaces its token and metadata in place.
        let wasPresent = accounts.contains { $0.id == account.id }
        var updated = accounts.filter { $0.id != account.id }
        updated.append(account)
        do {
            try store.save(updated)
        } catch {
            // Roll back the just-written token for a brand-new account so a failed
            // metadata write can't strand an orphan; a re-add keeps its valid token.
            if !wasPresent { try? credentialStore.deleteToken(login: verified.login, host: host) }
            addError = "Couldn't save the account."
            return
        }

        accounts = updated
        selectedAccountID = account.id
        resetDraft()
        isAddingAccount = false
    }

    func removeAccount(_ account: GitHubAccount) {
        removeError = nil
        // Metadata first: if the keychain delete later fails the account is
        // already gone from the list, never left listed-but-tokenless.
        let updated = accounts.filter { $0.id != account.id }
        do {
            try store.save(updated)
        } catch {
            removeError = "Couldn't update the account list."
            return
        }
        accounts = updated
        if selectedAccountID == account.id { selectedAccountID = accounts.first?.id }
        do {
            try credentialStore.deleteToken(login: account.login, host: account.host)
        } catch {
            removeError = "Couldn't remove the token from the keychain."
        }
    }

    // Fine-grained PATs expose no scopes (empty), so the hint only fires for a
    // classic token that is missing the push scope — never a false positive.
    func missingPushScope(for account: GitHubAccount) -> Bool {
        !account.scopes.isEmpty && !account.scopes.contains("repo")
    }

    func resetDraft() {
        draftHost = GitHubAccount.defaultHost
        draftToken = ""
        addError = nil
        deviceCode = nil
    }

    // User-facing strings live on the error types (LocalizedError.errorDescription);
    // fall back only for the rare non-LocalizedError that reaches the UI.
    nonisolated static func describe(_ error: any Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}
