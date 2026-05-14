import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String
    let branch: String
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
    IssueDetailTopBar(
        paddedID: "#00016",
        branch: "issue/00016-better-issue-details",
        onCopyID: {},
        onOpenRawEditor: {},
        onRevealInFinder: {},
        onClose: {}
    )
    .padding()
    .frame(width: 700)
}
