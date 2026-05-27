import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String?
    let branch: String?
    let showsCopyID: Bool
    let isCreating: Bool
    let saveDisabled: Bool
    let onCopyID: () -> Void
    let onSave: () -> Void

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
                Button("Save", systemImage: "square.and.arrow.down", action: onSave)
                    .help("Save changes (⌘S)")
                    .disabled(saveDisabled)
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.caption)
    }
}

#Preview {
    IssueDetailTopBar(
        paddedID: "#00041",
        branch: "issue/00041-card-body-tabs",
        showsCopyID: true,
        isCreating: false,
        saveDisabled: false,
        onCopyID: {},
        onSave: {}
    )
    .padding()
    .frame(width: 800)
}
