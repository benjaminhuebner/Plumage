import SwiftUI

struct InvalidIssueRowView: View {
    let folder: URL
    let error: FrontmatterError
    let padding: Int

    @State private var showPopover = false

    var body: some View {
        let parts = IssueDiscovery.extractID(fromFolderName: folder.lastPathComponent)
        HStack(spacing: 12) {
            Text(idText(parts.id))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            Text(parts.slug)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
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

    private func idText(_ id: Int?) -> String {
        if let id {
            return String(format: "%0\(max(padding, 1))d", id)
        }
        return String(repeating: "?", count: max(padding, 1))
    }
}

#Preview {
    List {
        InvalidIssueRowView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/00042-broken-stuff"),
            error: .invalidEnumValue(field: "status", value: "aproved"),
            padding: 5
        )
        InvalidIssueRowView(
            folder: URL(filePath: "/tmp/sample/.claude/issues/no-id-prefix"),
            error: .missingRequiredField(name: "branch"),
            padding: 5
        )
    }
}
