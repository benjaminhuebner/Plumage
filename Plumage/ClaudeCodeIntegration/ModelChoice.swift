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

    // Custom decode swallows unknown raw values and falls back to .default.
    // config.json could contain a stale alias from an older Plumage build (e.g.
    // a model name we later dropped); silently coercing to default keeps the
    // app loadable instead of erroring on a per-project basis.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ModelChoice(rawValue: raw) ?? .default
    }
}
