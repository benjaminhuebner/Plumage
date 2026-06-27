import Foundation

nonisolated enum EffortLevel: Hashable, Sendable, Codable {
    case `default`
    case low
    case medium
    case high
    case xhigh
    case max
    case ultracode

    // Unknown or removed levels load as `.default` so a stale config value
    // emits no flag and is dropped on the next write, never a crash.
    init(storageValue: String) {
        switch storageValue {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh": self = .xhigh
        case "max": self = .max
        case "ultracode": self = .ultracode
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
        case .ultracode: "ultracode"
        }
    }

    // The CLI rejects `--effort ultracode`, so it travels in --settings instead.
    var cliArg: [String] {
        switch self {
        case .default, .ultracode: []
        default: ["--effort", storageValue]
        }
    }

    // Empty for non-ultracode levels keeps the --settings JSON byte-identical to a flag-free run.
    var settingsOverrides: [String: Bool] {
        switch self {
        case .ultracode: ["ultracode": true]
        default: [:]
        }
    }

    // For spawn paths with no theme/hook --settings to merge into (chat); empty otherwise.
    var settingsCLIArgs: [String] {
        let overrides = settingsOverrides
        guard !overrides.isEmpty,
            let data = try? JSONSerialization.data(
                withJSONObject: overrides, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else { return [] }
        return ["--settings", json]
    }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        case .max: "Max"
        case .ultracode: "Ultracode"
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
