import SwiftUI

struct InvalidIssueCardView: View {
    let folder: URL
    let error: FrontmatterError
    let padding: Int

    @State private var showPopover = false

    var body: some View {
        let parts = IssueDiscovery.extractID(fromFolderName: folder.lastPathComponent)
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
        .contentShape(Rectangle())
        .help(error.summary)
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text(error.summary)
                    .font(.headline)
                Text(error.description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text(folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: 360, alignment: .leading)
        }
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
