import SwiftUI

struct IssueTitleRow: View {
    let titleDraft: Binding<String>
    let titlePlaceholder: String
    let autoFocusTitle: Bool
    let onCommitTitle: () -> Void
    let isDisabled: Bool
    let workflowBar: WorkflowBarConfig?

    struct WorkflowBarConfig {
        let status: IssueStatus
        let type: IssueType
        let draftBlocksImplement: Bool
        var openBlockers: [ResolvedBlocker] = []
        let runWorkflow: (WorkflowAction) -> Void
    }

    @FocusState private var titleFocused: Bool
    @State private var lastCommittedDraft: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField(titlePlaceholder, text: titleDraft)
                .font(.title2.weight(.bold))
                .textFieldStyle(.plain)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .focused($titleFocused)
                .disabled(isDisabled)
                .onSubmit(commitIfChanged)
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitIfChanged() }
                }
                .task {
                    if autoFocusTitle {
                        try? await Task.sleep(for: .milliseconds(50))
                        titleFocused = true
                    }
                }
            if let config = workflowBar {
                IssueWorkflowActionBar(
                    status: config.status,
                    type: config.type,
                    draftBlocksImplement: config.draftBlocksImplement,
                    openBlockers: config.openBlockers,
                    runWorkflow: config.runWorkflow
                )
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

#Preview("Loaded") {
    StatefulPreviewWrapper("Better Issue-Details View") { title in
        IssueTitleRow(
            titleDraft: title,
            titlePlaceholder: "Title",
            autoFocusTitle: false,
            onCommitTitle: {},
            isDisabled: false,
            workflowBar: .init(status: .inProgress, type: .feature, draftBlocksImplement: true) { _ in }
        )
        .padding()
        .frame(width: 700)
    }
}

#Preview("Creating") {
    StatefulPreviewWrapper("") { title in
        IssueTitleRow(
            titleDraft: title,
            titlePlaceholder: "Issue title",
            autoFocusTitle: false,
            onCommitTitle: {},
            isDisabled: false,
            workflowBar: nil
        )
        .padding()
        .frame(width: 700)
    }
}
