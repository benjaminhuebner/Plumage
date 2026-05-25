import SwiftUI

struct IssueDetailTopBar: View {
    // nil in creating mode (no ID/branch until allocation).
    let paddedID: String?
    let branch: String?
    let showsCopyID: Bool
    let saveDisabled: Bool
    let onCopyID: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if paddedID != nil || branch != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let paddedID {
                        Text(paddedID)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let branch {
                        Text(branch)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            if showsCopyID {
                Button("Copy ID", systemImage: "doc.on.doc", action: onCopyID)
                    .help("Copy folder name to clipboard")
            }
            Button("Save", systemImage: "square.and.arrow.down", action: onSave)
                .help("Save changes (⌘S)")
                .disabled(saveDisabled)
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
    }
}

#Preview {
    IssueDetailTopBar(
        paddedID: "#00041",
        branch: "issue/00041-card-body-tabs",
        showsCopyID: true,
        saveDisabled: false,
        onCopyID: {},
        onSave: {}
    )
    .padding()
    .frame(width: 800)
}
