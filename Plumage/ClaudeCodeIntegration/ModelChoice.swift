import Foundation

nonisolated enum ModelChoice: String, CaseIterable, Sendable, Codable {
    case `default`
    case opus
    case sonnet
    case haiku

    var cliArg: [String] {
        switch self {
        case .default: []
        case .opus: ["--model", "opus"]
        case .sonnet: ["--model", "sonnet"]
        case .haiku: ["--model", "haiku"]
        }
    }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }

    // `opusplan` is migrated to `.opus` rather than dropped: it always meant
    // the Opus model, and its plan-mode semantics now apply automatically.
    // Other unknown raw values coerce to `.default` so a stale config.json
    // from an older build still loads instead of failing per-project.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = ModelChoice(rawValue: raw) {
            self = known
        } else if raw == "opusplan" {
            self = .opus
        } else {
            self = .default
        }
    }
}
