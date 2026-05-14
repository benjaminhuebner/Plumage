import SwiftUI

struct IssueDetailHero: View {
    let status: IssueStatus
    let type: IssueType
    let labels: [String]
    let titleDraft: Binding<String>
    let titlePlaceholder: String
    let autoFocusTitle: Bool
    let onCommitTitle: () -> Void
    let onAddLabel: (String) -> Void
    let onRemoveLabel: (String) -> Void
    let isDisabled: Bool

    @FocusState private var titleFocused: Bool
    // Tracks the draft snapshot we last forwarded to the parent so that
    // Enter (onSubmit) followed by focus-loss doesn't double-fire the
    // commit. The model guards no-op writes by content too, but skipping
    // the second dispatch saves a needless detached task + disk read.
    @State private var lastCommittedDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                IssueStatusPill(status: status)
                IssueTypePill(type: type)
                LabelChipEditor(
                    labels: labels,
                    onAdd: onAddLabel,
                    onRemove: onRemoveLabel
                )
                .disabled(isDisabled)
                Spacer(minLength: 0)
            }
            TextField(titlePlaceholder, text: titleDraft)
                .font(.largeTitle.weight(.bold))
                .textFieldStyle(.plain)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($titleFocused)
                .disabled(isDisabled)
                .onSubmit(commitIfChanged)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitIfChanged() }
                }
                .task {
                    // The first focus assignment is dropped intermittently if
                    // it runs before the navigation push finishes animating;
                    // a single async hop after the view appears lands focus
                    // reliably (same trick as the prior sheet path).
                    if autoFocusTitle {
                        try? await Task.sleep(for: .milliseconds(50))
                        titleFocused = true
                    }
                }
        }
    }

    private func commitIfChanged() {
        let current = titleDraft.wrappedValue
        guard current != lastCommittedDraft else { return }
        lastCommittedDraft = current
        onCommitTitle()
    }
}

#Preview {
    StatefulPreviewWrapper("Better Issue-Details View") { title in
        IssueDetailHero(
            status: .inProgress,
            type: .feature,
            labels: ["ui", "ux"],
            titleDraft: title,
            titlePlaceholder: "Title",
            autoFocusTitle: false,
            onCommitTitle: {},
            onAddLabel: { _ in },
            onRemoveLabel: { _ in },
            isDisabled: false
        )
        .padding()
        .frame(width: 600)
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
