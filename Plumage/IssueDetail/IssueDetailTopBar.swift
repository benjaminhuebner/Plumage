import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String
    let branch: String
    let isBodyDirty: Bool
    let onCopyID: () -> Void
    let onOpenRawEditor: () -> Void
    let onRevealInFinder: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(paddedID)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if isBodyDirty {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Unsaved (⌘S)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Body has unsaved changes — save with Command S")
            }
            Spacer()
            Button("Copy ID", systemImage: "doc.on.doc", action: onCopyID)
                .help("Copy folder name to clipboard")
            Button("Open in raw editor", systemImage: "curlybraces", action: onOpenRawEditor)
                .help("Open spec.md in the raw markdown editor")
            Button("Reveal in Finder", systemImage: "folder", action: onRevealInFinder)
                .help("Show this issue's folder in Finder")
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close (⌘W)")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
    }
}

#Preview {
    VStack {
        IssueDetailTopBar(
            paddedID: "#00016",
            branch: "issue/00016-better-issue-details",
            isBodyDirty: false,
            onCopyID: {},
            onOpenRawEditor: {},
            onRevealInFinder: {},
            onClose: {}
        )
        IssueDetailTopBar(
            paddedID: "#00016",
            branch: "issue/00016-better-issue-details",
            isBodyDirty: true,
            onCopyID: {},
            onOpenRawEditor: {},
            onRevealInFinder: {},
            onClose: {}
        )
    }
    .padding()
    .frame(width: 700)
}
