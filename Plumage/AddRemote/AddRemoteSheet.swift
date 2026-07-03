import SwiftUI

struct AddRemoteSheet: View {
    @Bindable var model: AddRemoteModel
    let onDismiss: () -> Void
    var onAddAccount: (() -> Void)?
    @State private var submitTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Remote").font(.headline)

            Picker("Mode", selection: $model.mode) {
                Text("Existing").tag(AddRemoteModel.Mode.existing)
                Text("New on GitHub").tag(AddRemoteModel.Mode.newOnGitHub)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isWorking)

            Form { fields }
                .formStyle(.grouped)
                .disabled(model.isWorking)

            if let hint = model.validationHint, !isNoAccountNewMode {
                Label(hint, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            footer
        }
        .padding(20)
        .frame(width: 460)
        .task { await model.load() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { onDismiss() }
        }
        .onDisappear { submitTask?.cancel() }
    }

    private var isNoAccountNewMode: Bool {
        model.mode == .newOnGitHub && !model.hasAccounts
    }

    @ViewBuilder
    private var fields: some View {
        switch model.mode {
        case .existing:
            TextField("Name", text: $model.existingName)
            TextField("URL", text: $model.existingURL)
        case .newOnGitHub:
            newOnGitHubFields
        }
    }

    @ViewBuilder
    private var newOnGitHubFields: some View {
        if model.hasAccounts {
            if model.showsAccountPicker {
                Picker("Account", selection: $model.selectedAccountID) {
                    ForEach(model.accounts) { account in
                        Text(account.id).tag(Optional(account.id))
                    }
                }
            } else if let account = model.selectedAccount {
                LabeledContent("Account", value: account.id)
            }
            TextField("Repository Name", text: $model.newRepoName)
            Toggle("Private", isOn: $model.isPrivate)
            TextField("Remote Name", text: $model.newRemoteName)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a GitHub account to create a repository.")
                    .foregroundStyle(.secondary)
                if let onAddAccount {
                    Button("Add GitHub account…", action: onAddAccount)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if model.isWorking {
                ProgressView().controlSize(.small)
                Text("Working…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                submitTask?.cancel()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Add") {
                guard submitTask == nil else { return }
                submitTask = Task {
                    await model.submit()
                    submitTask = nil
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmit)
        }
    }
}

#Preview {
    AddRemoteSheet(
        model: AddRemoteModel(repoURL: URL(fileURLWithPath: "/tmp/demo-repo")),
        onDismiss: {})
}
