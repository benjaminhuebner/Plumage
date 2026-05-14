import SwiftUI

struct IssueDetailFormRows: View {
    let issue: Issue
    let titleDraft: Binding<String>
    let onCommitTitle: () -> Void
    let onSelectType: (IssueType) -> Void
    let onSelectStatus: (IssueStatus) -> Void
    let onAddLabel: (String) -> Void
    let onRemoveLabel: (String) -> Void
    let isDisabled: Bool

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Title") {
                TextField(
                    "title",
                    text: titleDraft,
                    onCommit: onCommitTitle
                )
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { onCommitTitle() }
                }
                .disabled(isDisabled)
            }

            row("Type") {
                Picker("", selection: typeBinding) {
                    ForEach(IssueType.allCases, id: \.self) { type in
                        HStack {
                            Circle().fill(type.color).frame(width: 10, height: 10)
                            Text(type.rawValue.capitalized)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(isDisabled)
            }

            row("Status") {
                Picker("", selection: statusBinding) {
                    ForEach(IssueStatus.allCases, id: \.self) { status in
                        HStack {
                            Circle().fill(status.indicatorColor).frame(width: 10, height: 10)
                            Text(status.label)
                        }
                        .tag(status)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(isDisabled)
            }

            row("Labels") {
                LabelChipEditor(
                    labels: issue.labels,
                    onAdd: onAddLabel,
                    onRemove: onRemoveLabel
                )
                .disabled(isDisabled)
            }

            row("Created") {
                Text(Self.formatted(issue.created))
                    .foregroundStyle(.secondary)
            }

            row("Updated") {
                Text(Self.formatted(issue.updated))
                    .foregroundStyle(.secondary)
            }

            row("Branch") {
                Text(issue.branch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func row<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(.secondary)
                .font(.callout)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var typeBinding: Binding<IssueType> {
        Binding(
            get: { issue.type },
            set: { onSelectType($0) }
        )
    }

    private var statusBinding: Binding<IssueStatus> {
        Binding(
            get: { issue.status },
            set: { onSelectStatus($0) }
        )
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    StatefulPreviewWrapper("Better Issue-Details View") { title in
        IssueDetailFormRows(
            issue: Issue(
                id: 16,
                folderName: "00016-better-issue-details",
                title: title.wrappedValue,
                type: .feature,
                status: .inProgress,
                created: Date(),
                updated: Date(),
                branch: "issue/00016-better-issue-details",
                labels: ["ui", "ux"],
                model: nil
            ),
            titleDraft: title,
            onCommitTitle: {},
            onSelectType: { _ in },
            onSelectStatus: { _ in },
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
