import SwiftUI

struct IssueWorkflowActionBar: View {
    static let aiGradient = LinearGradient(
        colors: [.orange, .pink, .purple, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    let status: IssueStatus
    let type: IssueType
    let draftBlocksImplement: Bool
    var openBlockers: [ResolvedBlocker] = []
    let runWorkflow: (WorkflowAction) -> Void

    @Environment(\.workflowCommandIsEmpty) private var workflowCommandIsEmpty

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WorkflowAction.allCases, id: \.self) { action in
                button(for: action)
            }
        }
    }

    @ViewBuilder
    private func button(for action: WorkflowAction) -> some View {
        let commandEmpty = workflowCommandIsEmpty(action, type)
        let enabled =
            action.isEnabled(status: status, draftBlocksImplement: draftBlocksImplement)
            && !commandEmpty
        let tooltip =
            commandEmpty
            ? "No command for this issue type."
            : action.disabledTooltip(status: status, draftBlocksImplement: draftBlocksImplement)
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
            if let warning = Self.blockedWarning(for: action, openBlockers: openBlockers) {
                core
                    .help(warning)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .offset(x: 4, y: -4)
                            .accessibilityHidden(true)
                    }
                    .accessibilityHint(warning)
            } else {
                core
            }
        } else {
            core.accessibilityHint(tooltip)
        }
    }

    nonisolated static func blockedWarning(
        for action: WorkflowAction, openBlockers: [ResolvedBlocker]
    ) -> String? {
        guard action == .implement, !openBlockers.isEmpty else { return nil }
        let names = openBlockers.map { blocker in
            blocker.id.map { "#" + IssueIDFormatter.padded($0, width: 5) } ?? blocker.folderName
        }
        return "Blocked by \(names.joined(separator: ", ")) — still open."
    }
}

#Preview("Draft / Feature") {
    IssueWorkflowActionBar(status: .draft, type: .feature, draftBlocksImplement: true) { _ in }
        .padding()
}

#Preview("Approved / Feature") {
    IssueWorkflowActionBar(status: .approved, type: .feature, draftBlocksImplement: true) { _ in }
        .padding()
}

#Preview("Waiting for review / Chore") {
    IssueWorkflowActionBar(status: .waitingForReview, type: .chore, draftBlocksImplement: false) {
        _ in
    }
    .padding()
}
