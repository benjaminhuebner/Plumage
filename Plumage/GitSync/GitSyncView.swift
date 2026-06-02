import SwiftUI

struct GitSyncView: View {
    @Bindable var model: GitSyncModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            outputView
            if model.isAuthBlocked {
                authBanner
            }
            footer
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 360)
        .task { model.start() }
        .onDisappear { model.cancel() }
        .task(id: model.state) {
            if await model.waitForAutoDismiss() { onDismiss() }
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
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(line.source == .stderr ? Color.secondary : Color.primary)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Credential prompt detected").font(.body.weight(.semibold))
                Text(
                    "Plumage cannot handle credential prompts. "
                        + "Configure your credential helper (osxkeychain, SSH key) "
                        + "and retry from the terminal."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if model.isRunning {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
