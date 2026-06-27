import Foundation

nonisolated enum ModelChoice: Hashable, Sendable, Codable {
    case `default`
    case fable
    case opus
    case sonnet
    case haiku
    case custom(String)

    // `opusplan` always meant Opus; its plan-mode semantics now apply automatically.
    // Other unknown strings stay verbatim — they may be valid CLI model names.
    init(storageValue: String) {
        switch storageValue {
        case "default": self = .default
        case "fable": self = .fable
        case "opus": self = .opus
        case "sonnet": self = .sonnet
        case "haiku": self = .haiku
        case "opusplan": self = .opus
        case "": self = .default
        default: self = .custom(storageValue)
        }
    }

    var storageValue: String {
        switch self {
        case .default: "default"
        case .fable: "fable"
        case .opus: "opus"
        case .sonnet: "sonnet"
        case .haiku: "haiku"
        case .custom(let value): value
        }
    }

    var cliArg: [String] {
        switch self {
        case .default: []
        case .fable: ["--model", "fable"]
        case .opus: ["--model", "opus"]
        case .sonnet: ["--model", "sonnet"]
        case .haiku: ["--model", "haiku"]
        case .custom(let value): ["--model", value]
        }
    }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .fable: "Fable"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        case .custom(let value): value
        }
    }

    // xhigh and ultracode are Opus/Fable only, Sonnet drops them, Haiku takes no
    // effort; unknown models offer every level and let claude reject what it can't honour.
    var supportedEfforts: [EffortLevel] {
        switch self {
        case .haiku: [.default]
        case .sonnet: [.default, .low, .medium, .high, .max]
        case .default, .fable, .opus, .custom:
            [.default, .low, .medium, .high, .xhigh, .max, .ultracode]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(storageValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}
