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

    // Completes missing types and collapses an all-identical map to .uniform.
    var normalized: WorkflowEffortSetting {
        switch self {
        case .uniform:
            return self
        case .perType(let map):
            var completed: [IssueType: EffortLevel] = [:]
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
            self = .uniform(EffortLevel(storageValue: string))
            return
        }
        let raw = try container.decode([String: String].self)
        var map: [IssueType: EffortLevel] = [:]
        for (key, value) in raw {
            // Unknown keys (a future issue type) load tolerantly, dropped on next write.
            guard let type = IssueType(rawValue: key) else { continue }
            map[type] = EffortLevel(storageValue: value)
        }
        self = WorkflowEffortSetting.perType(map).normalized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch normalized {
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
