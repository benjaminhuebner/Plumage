import SwiftUI

struct IssueWorkflowActionBar: View {
    static let aiGradient = LinearGradient(
        colors: [.orange, .pink, .purple, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    let status: IssueStatus
    let type: IssueType
    let runWorkflow: (WorkflowAction) -> Void

    @Environment(\.workflowCommandIsEmpty) private var workflowCommandIsEmpty

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
        let commandEmpty = workflowCommandIsEmpty(action, type)
        let enabled = action.isEnabled(status: status, type: type) && !commandEmpty
        let tooltip =
            commandEmpty
            ? "No command for this issue type."
            : action.disabledTooltip(status: status, type: type)
        let core = Button {
            runWorkflow(action)
        } label: {
            Label(action.label, systemImage: action.systemImage)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(
                    enabled ? AnyShapeStyle(Self.aiGradient) : AnyShapeStyle(.secondary)
                )
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
