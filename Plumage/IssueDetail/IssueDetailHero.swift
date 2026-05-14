import SwiftUI

struct IssueDetailHero: View {
    let issue: Issue
    let titleDraft: Binding<String>
    let onCommitTitle: () -> Void
    let isDisabled: Bool

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IssueStatusPill(status: issue.status)
                IssueTypePill(type: issue.type)
                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels, id: \.self) { label in
                            LabelChip(text: label)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            TextField("Title", text: titleDraft)
                .font(.largeTitle.weight(.bold))
                .textFieldStyle(.plain)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($titleFocused)
                .disabled(isDisabled)
                .onSubmit(onCommitTitle)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { onCommitTitle() }
                }
        }
    }
}

#Preview {
    StatefulPreviewWrapper("Better Issue-Details View") { title in
        IssueDetailHero(
            issue: Issue(
                id: 16,
                folderName: "00016-better-issue-details",
                title: title.wrappedValue,
                type: .feature,
                status: .inProgress,
                created: .distantPast,
                updated: .distantPast,
                branch: "issue/00016-better-issue-details",
                labels: ["ui", "ux"],
                model: nil
            ),
            titleDraft: title,
            onCommitTitle: {},
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
