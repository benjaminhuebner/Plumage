import Foundation

nonisolated struct ProjectConfig: Codable, Hashable, Sendable {
    let name: String
    let schemaVersion: Int
    let issueIdPadding: Int?
    let git: GitConfig?
    var workflows: WorkflowsConfig?
    var models: ModelsConfig?

    var gitDefaultBranch: String {
        git?.defaultBranch ?? "main"
    }
}

nonisolated struct GitConfig: Codable, Hashable, Sendable {
    let defaultBranch: String?
}

nonisolated struct WorkflowsConfig: Codable, Hashable, Sendable {
    var plan: WorkflowOverride?
    var implement: WorkflowOverride?
    var review: WorkflowOverride?

    subscript(action: WorkflowAction) -> WorkflowOverride? {
        get {
            switch action {
            case .plan: return plan
            case .implement: return implement
            case .review: return review
            }
        }
        set {
            switch action {
            case .plan: plan = newValue
            case .implement: implement = newValue
            case .review: review = newValue
            }
        }
    }
}

nonisolated struct WorkflowOverride: Codable, Hashable, Sendable {
    var command: String
    var permissionMode: PermissionMode?

    init(command: String = "", permissionMode: PermissionMode? = nil) {
        self.command = command
        self.permissionMode = permissionMode
    }

    private enum CodingKeys: String, CodingKey {
        case command, permissionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // command is optional in JSON — old configs only have a command string,
        // new configs may have only permissionMode. Default to "" when absent.
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        permissionMode = try container.decodeIfPresent(
            PermissionMode.self, forKey: .permissionMode
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Omit command key entirely when empty to keep config.json clean.
        if !command.isEmpty {
            try container.encode(command, forKey: .command)
        }
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
    }
}

nonisolated struct ModelsConfig: Codable, Hashable, Sendable {
    var chat: ModelChoice?
    var terminals: ModelChoice?
    var plan: ModelChoice?
    var implement: ModelChoice?
    var review: ModelChoice?

    // Plumage's opinionated per-slot defaults. Used both as the initial picker
    // value when no override is set on disk and as the fallback ModelChoice
    // for session-spawning consumers (ProjectWindow, TerminalTabsModel).
    static let chatDefault: ModelChoice = .opus
    static let terminalsDefault: ModelChoice = .opus
    static let planDefault: ModelChoice = .opusPlan
    static let implementDefault: ModelChoice = .opus
    static let reviewDefault: ModelChoice = .opus

    func workflow(_ action: WorkflowAction) -> ModelChoice? {
        switch action {
        case .plan: return plan
        case .implement: return implement
        case .review: return review
        }
    }

    var chatResolved: ModelChoice { chat ?? Self.chatDefault }
    var terminalsResolved: ModelChoice { terminals ?? Self.terminalsDefault }

    func workflowResolved(_ action: WorkflowAction) -> ModelChoice {
        switch action {
        case .plan: plan ?? Self.planDefault
        case .implement: implement ?? Self.implementDefault
        case .review: review ?? Self.reviewDefault
        }
    }

    static func slotDefault(for slot: ModelSlot) -> ModelChoice {
        switch slot {
        case .chat: chatDefault
        case .terminals: terminalsDefault
        case .planAction: planDefault
        case .implementAction: implementDefault
        case .reviewAction: reviewDefault
        }
    }
}

nonisolated enum ModelSlot: Sendable, Hashable, CaseIterable {
    case chat
    case terminals
    case planAction
    case implementAction
    case reviewAction

    var label: String {
        switch self {
        case .chat: "Chat"
        case .terminals: "Terminals"
        case .planAction: "Plan Button"
        case .implementAction: "Implement Button"
        case .reviewAction: "Review Button"
        }
    }
}
