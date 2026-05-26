import SwiftUI

struct IssueWorkflowActionBar: View {
    let status: IssueStatus
    let type: IssueType
    let runWorkflow: (WorkflowAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WorkflowAction.allCases, id: \.self) { action in
                button(for: action)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func button(for action: WorkflowAction) -> some View {
        let enabled = action.isEnabled(status: status, type: type)
        let tooltip = action.disabledTooltip(status: status, type: type)
        let core = Button {
            runWorkflow(action)
        } label: {
            Label(action.label, systemImage: action.systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!enabled)
        .help(enabled ? action.label : tooltip)
        .accessibilityLabel(action.label)

        // Apply accessibilityHint only on disabled buttons; an empty hint
        // string still gets published, which VoiceOver may announce as
        // silence after the label.
        if enabled {
            core
        } else {
            core.accessibilityHint(tooltip)
        }
    }
}

#Preview("Draft / Feature") {
    IssueWorkflowActionBar(status: .draft, type: .feature) { _ in }
        .padding()
}

#Preview("Approved / Feature") {
    IssueWorkflowActionBar(status: .approved, type: .feature) { _ in }
        .padding()
}

#Preview("Waiting for review / Chore") {
    IssueWorkflowActionBar(status: .waitingForReview, type: .chore) { _ in }
        .padding()
}
