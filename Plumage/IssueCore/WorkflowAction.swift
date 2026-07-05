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
        case .plan: "Plan"
        case .implement: "Implement"
        case .review: "Review"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "sparkles"
        case .implement: "hammer"
        case .review: "checkmark.seal"
        }
    }

    // Static, model-independent permission-mode mapping. Plan always runs in
    // `--permission-mode plan`; Implement accepts edits; Review uses default.
    // The mode is decoupled from the model choice — Plan stays plan-mode for
    // any of opus / sonnet / haiku. A per-action override in config.json can
    // replace this default (see WorkflowModePickerRow).
    var permissionMode: PermissionMode {
        switch self {
        case .plan: .plan
        case .implement: .acceptEdits
        case .review: .default
        }
    }

    var modelSlot: ModelSlot {
        switch self {
        case .plan: .planAction
        case .implement: .implementAction
        case .review: .reviewAction
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

    static func available(status: IssueStatus, draftBlocksImplement: Bool) -> WorkflowAction? {
        allCases.first { $0.isEnabled(status: status, draftBlocksImplement: draftBlocksImplement) }
    }

    // draftBlocksImplement is the issue type's catalog flag: types with the
    // flag on are planned first; types with it off implement straight from draft.
    func isEnabled(status: IssueStatus, draftBlocksImplement: Bool) -> Bool {
        switch self {
        case .plan:
            return status == .draft && draftBlocksImplement
        case .implement:
            if status == .approved || status == .inProgress { return true }
            if status == .draft, !draftBlocksImplement { return true }
            return false
        case .review:
            return status == .waitingForReview
        }
    }

    func disabledTooltip(status: IssueStatus, draftBlocksImplement: Bool) -> String {
        if status == .done { return "Issue is done." }
        if status == .blocked { return "Issue is blocked." }
        switch self {
        case .plan:
            if status == .draft && !draftBlocksImplement {
                return "This issue type skips planning — it goes directly to Implement."
            }
            return "Issue is already approved or further along."
        case .implement:
            return "Issue must be planned first (Plan button)."
        case .review:
            return "Issue is not yet implemented."
        }
    }
}
