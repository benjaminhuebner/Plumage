import Foundation

nonisolated enum PermissionMode: String, CaseIterable, Codable, Sendable {
    case plan
    case acceptEdits
    case auto
    case bypassPermissions
    case `default`
    case dontAsk

    // Tolerant Codable path: a mode from a newer claude must not make the
    // whole project fail to open; .default is the restrictive coercion.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = PermissionMode(rawValue: raw) ?? .default
    }

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
