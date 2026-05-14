import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String
    let branch: String
    @Binding var displayMode: IssueDetailView.DisplayMode
    let onCopyID: () -> Void
    let onRevealInFinder: () -> Void
    let onSave: () -> Void

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
            DisplayModeToggle(displayMode: $displayMode)
                .help("Switch between detail and raw spec.md view")
            Button("Copy ID", systemImage: "doc.on.doc", action: onCopyID)
                .help("Copy folder name to clipboard")
            Button("Reveal in Finder", systemImage: "folder", action: onRevealInFinder)
                .help("Show this issue's folder in Finder")
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Save changes (⌘S)")
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
            onCopyID: {},
            onRevealInFinder: {},
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
