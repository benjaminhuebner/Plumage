import Foundation

nonisolated enum PermissionMode: String, CaseIterable, Sendable {
    case plan
    case acceptEdits
    case `default`

    var rawCLIValue: String {
        switch self {
        case .plan: "plan"
        case .acceptEdits: "acceptEdits"
        case .default: "default"
        }
    }
}
