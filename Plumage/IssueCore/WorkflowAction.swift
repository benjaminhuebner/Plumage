import Foundation

nonisolated enum WorkflowAction: String, CaseIterable, Sendable, Codable {
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

    var permissionMode: PermissionMode {
        switch self {
        case .plan: .plan
        case .implement: .acceptEdits
        case .review: .default
        }
    }

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
