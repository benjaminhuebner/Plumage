import SwiftUI

nonisolated enum WorkflowAction: String, CaseIterable, Sendable {
    case plan
    case implement
    case review

    var slug: String {
        switch self {
        case .plan: "plumage-plan"
        case .implement: "plumage-implement"
        case .review: "plumage-review"
        }
    }

    var label: String {
        switch self {
        case .plan: "Plan with Plumage"
        case .implement: "Implement with Plumage"
        case .review: "Review with Plumage"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "sparkles"
        case .implement: "hammer"
        case .review: "checkmark.seal"
        }
    }

    // Drives the claude `--permission-mode <value>` flag for the workflow tab.
    // Mapping rationale: plan stays sandboxed during planning; implement gets
    // acceptEdits so the agent can write code without prompt-fatigue; review
    // is read-mostly and uses default (prompt-on-side-effect).
    var permissionMode: PermissionMode {
        switch self {
        case .plan: .plan
        case .implement: .acceptEdits
        case .review: .default
        }
    }

    // "<Action>: <slug>" — used by TerminalTabsModel.findWorkflowTab as the
    // exact match key. Action is capitalized; slug is passed through verbatim.
    func tabTitle(slug: String) -> String {
        let action: String
        switch self {
        case .plan: action = "Plan"
        case .implement: action = "Implement"
        case .review: action = "Review"
        }
        return "\(action): \(slug)"
    }

    func isEnabled(status: IssueStatus, type: IssueType) -> Bool {
        switch self {
        case .plan:
            return status == .draft && type == .feature
        case .implement:
            if status == .approved || status == .inProgress { return true }
            // Draft + non-feature skips the Plan step entirely. The Plan
            // button's tooltip promises chore/spike/refactor "gehen direkt
            // in Implement" — refactor must therefore be enabled here too,
            // otherwise a draft refactor has no enabled button at all.
            if status == .draft, type != .feature { return true }
            return false
        case .review:
            return status == .waitingForReview
        }
    }

    func disabledTooltip(status: IssueStatus, type: IssueType) -> String {
        if status == .done { return "Issue ist abgeschlossen." }
        if status == .blocked { return "Issue ist blockiert." }
        switch self {
        case .plan:
            if status == .draft && type != .feature {
                return "Nur Feature-Issues werden geplant — chore/spike/refactor gehen direkt in Implement."
            }
            return "Issue ist bereits approved oder weiter."
        case .implement:
            return "Issue muss erst geplant werden (Plan-Button)."
        case .review:
            return "Issue ist noch nicht implementiert."
        }
    }
}

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
