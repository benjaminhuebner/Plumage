import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String?
    let branch: String?
    let showsCopyID: Bool
    let isCreating: Bool
    let autoSaveStatus: IssueDetailModel.AutoSaveStatus
    let onCopyID: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let paddedID {
                Text(paddedID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if paddedID != nil, branch != nil {
                Text("|")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
            if let branch {
                Text(branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if showsCopyID {
                Button("Copy ID", systemImage: "doc.on.doc", action: onCopyID)
                    .help("Copy folder name to clipboard")
            }
            if !isCreating {
                autoSaveBadge
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.caption)
    }

    @ViewBuilder
    private var autoSaveBadge: some View {
        switch autoSaveStatus {
        case .saving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Saving…")
            }
            .foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            HStack(spacing: 4) {
                Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
        case .idle:
            EmptyView()
        }
    }
}

#Preview {
    IssueDetailTopBar(
        paddedID: "#00041",
        branch: "issue/00041-card-body-tabs",
        showsCopyID: true,
        isCreating: false,
        autoSaveStatus: .saved,
        onCopyID: {},
        onRetry: {}
    )
    .padding()
    .frame(width: 800)
}
