nonisolated enum WorkflowEffortSetting: Hashable, Sendable, Codable {
    case uniform(EffortLevel)
    case perType([IssueType: EffortLevel])

    // nil = no concrete value; the slot default lives in EffortsConfig.
    func choice(for type: IssueType) -> EffortLevel? {
        switch self {
        case .uniform(let level): level
        case .perType(let map): map[type]
        }
    }

    // Completes missing types from the given catalog list and collapses an
    // all-identical map to .uniform. Entries for types no longer in the
    // catalog are dropped.
    func normalized(for types: [IssueType]) -> WorkflowEffortSetting {
        switch self {
        case .uniform:
            return self
        case .perType(let map):
            var completed: [IssueType: EffortLevel] = [:]
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
            self = .uniform(EffortLevel(storageValue: string))
            return
        }
        // Types are user-defined, so every key loads; normalization against
        // the catalog happens in ProjectSettingsModel.
        let raw = try container.decode([String: String].self)
        var map: [IssueType: EffortLevel] = [:]
        for (key, value) in raw {
            map[IssueType(rawValue: key)] = EffortLevel(storageValue: value)
        }
        self = .perType(map)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .uniform(let level):
            try container.encode(level.storageValue)
        case .perType(let map):
            var raw: [String: String] = [:]
            for (type, level) in map {
                raw[type.rawValue] = level.storageValue
            }
            try container.encode(raw)
        }
    }
}
