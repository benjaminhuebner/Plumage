import SwiftUI

struct IssueDetailTopBar: View {
    let paddedID: String
    let branch: String
    let isBodyDirty: Bool
    @Binding var displayMode: IssueDetailView.DisplayMode
    let onCopyID: () -> Void
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
                .accessibilityLabel("Unsaved changes — save with Command S")
            }
            Spacer()
            Picker("View", selection: $displayMode) {
                ForEach(IssueDetailView.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .help("Switch between detail and raw spec.md view")
            Button("Copy ID", systemImage: "doc.on.doc", action: onCopyID)
                .help("Copy folder name to clipboard")
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
    StatefulPreviewWrapper(IssueDetailView.DisplayMode.detail) { mode in
        VStack {
            IssueDetailTopBar(
                paddedID: "#00016",
                branch: "issue/00016-better-issue-details",
                isBodyDirty: false,
                displayMode: mode,
                onCopyID: {},
                onRevealInFinder: {},
                onClose: {}
            )
            IssueDetailTopBar(
                paddedID: "#00016",
                branch: "issue/00016-better-issue-details",
                isBodyDirty: true,
                displayMode: mode,
                onCopyID: {},
                onRevealInFinder: {},
                onClose: {}
            )
        }
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
