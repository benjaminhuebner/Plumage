import SwiftUI

struct InvalidIssueCardView: View {
    let folder: URL
    let error: FrontmatterError
    let padding: Int

    @Environment(\.kanbanHighlightedID) private var highlightedID: String?

    private var folderName: String { folder.lastPathComponent }

    private var isHighlighted: Bool {
        highlightedID == folderName
    }

    var body: some View {
        let parts = IssueDiscovery.extractID(fromFolderName: folderName)
        VStack(alignment: .leading, spacing: 6) {
            Text(parts.slug)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(IssueIDFormatter.paddedOrPlaceholder(parts.id, width: padding))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.red, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isHighlighted ? 1.0 : 0.0)
                .animation(.easeOut(duration: 1.0), value: isHighlighted)
        )
        .contentShape(Rectangle())
        .help(error.summary)
        .accessibilityLabel("Invalid issue: \(error.summary)")
    }
}

#Preview {
    VStack(spacing: 8) {
        InvalidIssueCardView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
            error: .invalidEnumValue(field: "status", value: "aproved"),
            padding: 5
        )
        InvalidIssueCardView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/no-id-prefix"),
            error: .missingRequiredField(name: "branch"),
            padding: 5
        )
    }
    .padding()
    .frame(width: 260)
}
