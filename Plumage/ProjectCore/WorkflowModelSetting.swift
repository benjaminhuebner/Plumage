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

    // Completes missing types from the given catalog list and collapses an
    // all-identical map to .uniform so disk mirrors the UI semantics. Entries
    // for types no longer in the catalog are dropped.
    func normalized(for types: [IssueType]) -> WorkflowModelSetting {
        switch self {
        case .uniform:
            return self
        case .perType(let map):
            var completed: [IssueType: ModelChoice] = [:]
            for type in types {
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
        // Types are user-defined, so every key loads; the catalog isn't known
        // here — normalization happens where it is (ProjectSettingsModel).
        let raw = try container.decode([String: String].self)
        var map: [IssueType: ModelChoice] = [:]
        for (key, value) in raw {
            map[IssueType(rawValue: key)] = ModelChoice(storageValue: value)
        }
        self = .perType(map)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
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
