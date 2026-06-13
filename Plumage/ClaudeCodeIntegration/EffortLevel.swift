import Foundation

nonisolated enum EffortLevel: Hashable, Sendable, Codable {
    case `default`
    case low
    case medium
    case high
    case xhigh
    case max

    // Unknown or removed levels load as `.default` so a stale config value
    // emits no flag and is dropped on the next write, never a crash.
    init(storageValue: String) {
        switch storageValue {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh": self = .xhigh
        case "max": self = .max
        default: self = .default
        }
    }

    var storageValue: String {
        switch self {
        case .default: "default"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .max: "max"
        }
    }

    var cliArg: [String] {
        switch self {
        case .default: []
        default: ["--effort", storageValue]
        }
    }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        case .max: "Max"
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
