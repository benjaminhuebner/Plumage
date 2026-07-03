import SwiftUI

struct AccountsSettingsTab: View {
    @State private var model = AccountsSettingsModel()
    @State private var pendingRemoval: GitHubAccount?
    @State private var showRemoveConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                accountList
                Divider()
                bottomBar
            }
            .frame(width: 180)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.reload() }
        .sheet(isPresented: $model.isAddingAccount) {
            AddGitHubAccountSheet(model: model)
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove “\($0.login)”?" } ?? "",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { account in
            Button("Remove Account", role: .destructive) { model.removeAccount(account) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the account and deletes its token from your keychain.")
        }
    }

    private var accountList: some View {
        List(selection: $model.selectedAccountID) {
            ForEach(model.accounts) { account in
                row(for: account).tag(account.id)
            }
        }
        .listStyle(.inset)
    }

    private func row(for account: GitHubAccount) -> some View {
        HStack(spacing: 8) {
            GitHubAvatarView(url: account.avatarURL, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.login).font(.body)
                Text(account.host).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            Button {
                model.beginAdd()
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Add Account")

            Button {
                requestRemoval(model.selectedAccount)
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedAccount == nil)
            .help("Remove Account")

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let account = model.selectedAccount {
            detail(for: account)
        } else {
            ContentUnavailableView(
                "No Account Selected",
                systemImage: "person.crop.circle",
                description: Text(
                    model.accounts.isEmpty
                        ? "Click + to add a GitHub account."
                        : "Select an account to see its details."))
        }
    }

    private func detail(for account: GitHubAccount) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GitHubAvatarView(url: account.avatarURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? account.login).font(.headline)
                    Text("@\(account.login) · \(account.host)")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if !account.scopes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scopes").font(.caption).foregroundStyle(.secondary)
                    Text(account.scopes.joined(separator: ", ")).font(.callout)
                }
            }

            if model.missingPushScope(for: account) {
                Label(
                    "This token has no “repo” scope — pushes may be rejected.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout).foregroundStyle(.secondary)
            }

            if let removeError = model.removeError {
                Label(removeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            }

            Spacer()

            Button("Remove Account…", role: .destructive) { requestRemoval(account) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestRemoval(_ account: GitHubAccount?) {
        guard let account else { return }
        pendingRemoval = account
        showRemoveConfirmation = true
    }
}
