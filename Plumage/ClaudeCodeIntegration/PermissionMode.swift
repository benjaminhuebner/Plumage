nonisolated enum PermissionMode: String, CaseIterable, Codable, Sendable {
    case plan
    case acceptEdits
    case auto
    case bypassPermissions
    case `default`
    case dontAsk

    var rawCLIValue: String {
        switch self {
        case .plan: "plan"
        case .acceptEdits: "acceptEdits"
        case .auto: "auto"
        case .bypassPermissions: "bypassPermissions"
        case .default: "default"
        case .dontAsk: "dontAsk"
        }
    }

    var displayName: String {
        switch self {
        case .plan: "Plan"
        case .acceptEdits: "Accept Edits"
        case .auto: "Auto"
        case .bypassPermissions: "Bypass Permissions"
        case .default: "Default"
        case .dontAsk: "Don't Ask"
        }
    }
}
