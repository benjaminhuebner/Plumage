import SwiftUI

struct GitSyncView: View {
    @Bindable var model: GitSyncModel
    let onDismiss: () -> Void
    var onAddAccount: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isConfiguring {
                configForm
                Spacer(minLength: 0)
            } else {
                outputView
                if model.isAuthBlocked {
                    authBanner
                } else if let login = model.credentialRejectedLogin {
                    credentialRejectedBanner(login: login)
                }
            }
            footer
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: model.isConfiguring ? 220 : 360)
        .task { await startOrConfigure() }
        .onDisappear { model.cancel() }
        .task(id: model.state) {
            if await model.waitForAutoDismiss() { onDismiss() }
        }
    }

    // Push opens on the options form and loads its remotes; pull runs immediately.
    private func startOrConfigure() async {
        if model.isConfiguring {
            await model.loadRemotes()
        } else {
            model.start()
        }
    }

    @ViewBuilder
    private var configForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let branch = model.currentBranch {
                labeledRow("Branch") {
                    Text(branch).foregroundStyle(.secondary)
                }
            }
            labeledRow("Remote") {
                if model.isLoadingRemotes {
                    ProgressView().controlSize(.small)
                } else if model.availableRemotes.isEmpty {
                    Text("No remotes configured").foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $model.pushRemote) {
                        ForEach(model.availableRemotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Include tags", isOn: $model.includeTags)
                Text("Pushes the branch plus the annotated tags reachable from it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Force (with lease)", isOn: $model.forcePush)
                Text("Refuses to overwrite if the remote moved since your last fetch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledRow<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if case .finished(let exit) = model.state, exit == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if model.isAuthBlocked || model.didFail {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Text(model.headerTitle)
                .font(.headline)
            if let login = model.usingAccountLogin {
                Text("as @\(login)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.didRetryWithUpstream {
                Text("(retried with --set-upstream)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var outputView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(model.lines) { item in
                    Text(item.line.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(item.line.source == .stderr ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var authBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Credential prompt detected").font(.body.weight(.semibold))
                Text(
                    "No GitHub account is set up for this repository. Add one to push "
                        + "and pull without leaving Plumage, or configure a credential "
                        + "helper and retry from the terminal."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let onAddAccount {
                    Button("Add GitHub account…", action: onAddAccount)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func credentialRejectedBanner(login: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Authentication failed").font(.body.weight(.semibold))
                Text(
                    "GitHub rejected the token for @\(login). It may be expired or lack "
                        + "push access — re-add the account to update its token."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let onAddAccount {
                    Button("Update GitHub account…", action: onAddAccount)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if model.isConfiguring {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Push") { model.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.availableRemotes.isEmpty)
            } else if model.isRunning {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
