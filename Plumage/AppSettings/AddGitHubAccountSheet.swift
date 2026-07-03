import SwiftUI

struct AddGitHubAccountSheet: View {
    @Bindable var model: AccountsSettingsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var signInTask: Task<Void, Never>?

    private static let tokenCreationURL: URL = {
        guard let url = URL(string: "https://github.com/settings/personal-access-tokens/new") else {
            preconditionFailure("invalid GitHub token-creation URL literal")
        }
        return url
    }()

    private var canAdd: Bool {
        !model.draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isVerifying && !model.isSigningIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add GitHub Account").font(.headline)

            if model.isOAuthConfigured {
                oauthSection
            }

            Form {
                TextField("Host", text: $model.draftHost)
                SecureField("Token", text: $model.draftToken)
                Link("Create a token on GitHub…", destination: Self.tokenCreationURL)
                    .font(.callout)
            }
            .formStyle(.grouped)
            .disabled(model.isSigningIn)

            if let error = model.addError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                if model.isVerifying {
                    ProgressView().controlSize(.small)
                    Text("Verifying…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    signInTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    signInTask = Task {
                        await model.addAccount()
                        signInTask = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: model.deviceCode) { _, code in
            if let code { openURL(code.verificationURL) }
        }
        .onDisappear { signInTask?.cancel() }
    }

    @ViewBuilder
    private var oauthSection: some View {
        if let code = model.deviceCode {
            VStack(spacing: 8) {
                Text("Enter this code at github.com/login/device:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(code.userCode)
                    .font(.title2.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 6) {
                Button {
                    signInTask = Task {
                        await model.signInWithGitHub()
                        signInTask = nil
                    }
                } label: {
                    Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(model.isSigningIn)
                Text("or add a token manually")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
