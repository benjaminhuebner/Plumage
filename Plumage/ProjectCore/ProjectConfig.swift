nonisolated struct ProjectConfig: Codable, Hashable, Sendable {
    let name: String
    let schemaVersion: Int
    let issueIdPadding: Int?
    let git: GitConfig?
    var workflows: WorkflowsConfig?
    var models: ModelsConfig?
    var efforts: EffortsConfig?

    var gitDefaultBranch: String {
        git?.defaultBranch ?? "main"
    }

    var githubAccountID: String? {
        git?.githubAccountID
    }
}

nonisolated struct GitConfig: Codable, Hashable, Sendable {
    let defaultBranch: String?
    var githubAccountID: String?

    init(defaultBranch: String?, githubAccountID: String? = nil) {
        self.defaultBranch = defaultBranch
        self.githubAccountID = githubAccountID
    }
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
        // Unknown modes decode as nil, not a coerced concrete mode: coercion
        // would override the action's safer mode (plan) and get persisted
        // back over the user's hand-authored value.
        let rawMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        permissionMode = rawMode.flatMap { PermissionMode(rawValue: $0) }
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
    var plan: WorkflowModelSetting?
    var implement: WorkflowModelSetting?
    var review: WorkflowModelSetting?

    // Per-slot fallbacks when no override is set on disk: .default passes no
    // --model flag, so the session runs with whatever the CLI itself resolves.
    static let chatDefault: ModelChoice = .default
    static let terminalsDefault: ModelChoice = .default
    static let planDefault: ModelChoice = .default
    static let implementDefault: ModelChoice = .default
    static let reviewDefault: ModelChoice = .default

    func workflow(_ action: WorkflowAction) -> WorkflowModelSetting? {
        switch action {
        case .plan: return plan
        case .implement: return implement
        case .review: return review
        }
    }

    var chatResolved: ModelChoice { chat ?? Self.chatDefault }
    var terminalsResolved: ModelChoice { terminals ?? Self.terminalsDefault }

    func workflowResolved(_ action: WorkflowAction, type: IssueType) -> ModelChoice {
        workflow(action)?.choice(for: type) ?? Self.slotDefault(for: action.modelSlot)
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

nonisolated struct EffortsConfig: Codable, Hashable, Sendable {
    var chat: EffortLevel?
    var terminals: EffortLevel?
    var plan: WorkflowEffortSetting?
    var implement: WorkflowEffortSetting?
    var review: WorkflowEffortSetting?

    // Every slot defaults to .default → no --effort flag, claude's own default.
    static let chatDefault: EffortLevel = .default
    static let terminalsDefault: EffortLevel = .default
    static let planDefault: EffortLevel = .default
    static let implementDefault: EffortLevel = .default
    static let reviewDefault: EffortLevel = .default

    func workflow(_ action: WorkflowAction) -> WorkflowEffortSetting? {
        switch action {
        case .plan: return plan
        case .implement: return implement
        case .review: return review
        }
    }

    var chatResolved: EffortLevel { chat ?? Self.chatDefault }
    var terminalsResolved: EffortLevel { terminals ?? Self.terminalsDefault }

    func workflowResolved(_ action: WorkflowAction, type: IssueType) -> EffortLevel {
        workflow(action)?.choice(for: type) ?? Self.slotDefault(for: action.modelSlot)
    }

    static func slotDefault(for slot: ModelSlot) -> EffortLevel {
        switch slot {
        case .chat: chatDefault
        case .terminals: terminalsDefault
        case .planAction: planDefault
        case .implementAction: implementDefault
        case .reviewAction: reviewDefault
        }
    }
}
