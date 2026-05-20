import SwiftUI

struct IssueDetailTopBar: View {
    // nil in creating mode (no ID/branch until allocation).
    let paddedID: String?
    let branch: String?
    @Binding var displayMode: IssueDetailView.DisplayMode
    let showsDisplayModeToggle: Bool
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
            if showsDisplayModeToggle {
                DisplayModeToggle(displayMode: $displayMode)
                    .help("Switch between detail and raw spec.md view")
            }
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
    StatefulPreviewWrapper(IssueDetailView.DisplayMode.detail) { mode in
        IssueDetailTopBar(
            paddedID: "#00016",
            branch: "issue/00016-better-issue-details",
            displayMode: mode,
            showsDisplayModeToggle: true,
            showsCopyID: true,
            saveDisabled: false,
            onCopyID: {},
            onSave: {}
        )
        .padding()
        .frame(width: 800)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
