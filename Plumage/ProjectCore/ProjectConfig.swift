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

    init(command: String) {
        self.command = command
    }
}

nonisolated struct ModelsConfig: Codable, Hashable, Sendable {
    var chat: ModelChoice?
    var terminals: ModelChoice?
    var plan: ModelChoice?
    var implement: ModelChoice?
    var review: ModelChoice?

    func workflow(_ action: WorkflowAction) -> ModelChoice? {
        switch action {
        case .plan: return plan
        case .implement: return implement
        case .review: return review
        }
    }
}
