import Foundation

nonisolated enum WorkflowModelSetting: Hashable, Sendable, Codable {
    case uniform(ModelChoice)
    case perType([IssueType: ModelChoice])

    // nil = no concrete value; slot-default knowledge stays in ModelsConfig.
    func choice(for type: IssueType) -> ModelChoice? {
        switch self {
        case .uniform(let choice): choice
        case .perType(let map): map[type]
        }
    }

    var uniformValue: ModelChoice? {
        if case .uniform(let choice) = self { return choice }
        return nil
    }

    // Completes missing types and collapses an all-identical map to .uniform
    // so disk mirrors the UI semantics.
    var normalized: WorkflowModelSetting {
        switch self {
        case .uniform:
            return self
        case .perType(let map):
            var completed: [IssueType: ModelChoice] = [:]
            for type in IssueType.allCases {
                completed[type] = map[type] ?? .default
            }
            let values = Set(completed.values)
            if let only = values.first, values.count == 1 {
                return .uniform(only)
            }
            return .perType(completed)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .uniform(ModelChoice(storageValue: string))
            return
        }
        let raw = try container.decode([String: String].self)
        var map: [IssueType: ModelChoice] = [:]
        for (key, value) in raw {
            // Unknown keys (a future issue type) load tolerantly, dropped on next write.
            guard let type = IssueType(rawValue: key) else { continue }
            map[type] = ModelChoice(storageValue: value)
        }
        self = WorkflowModelSetting.perType(map).normalized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch normalized {
        case .uniform(let choice):
            try container.encode(choice.storageValue)
        case .perType(let map):
            var raw: [String: String] = [:]
            for (type, choice) in map {
                raw[type.rawValue] = choice.storageValue
            }
            try container.encode(raw)
        }
    }
}
