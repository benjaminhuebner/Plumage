nonisolated enum TemplateArchiveManifestError: Error, Equatable {
    case newerSchema(found: Int, supported: Int)
}

// Forward-compat mirrors TemplateManifest (unknown keys ignored, missing
// collections empty), but a schemaVersion above ours throws `newerSchema`
// before any content key is read — the importer turns that into a clear message.
nonisolated struct TemplateArchiveManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let base: BaseTemplate?
    let categories: [TemplateCategory]
    let sharedComponents: [SharedComponent]
    let templates: [TemplateDescriptor]
    let tombstones: [Tombstone]
    let hookWirings: [HookWiring]

    init(
        schemaVersion: Int = TemplateArchiveManifest.currentSchemaVersion,
        base: BaseTemplate? = nil,
        categories: [TemplateCategory] = [],
        sharedComponents: [SharedComponent] = [],
        templates: [TemplateDescriptor] = [],
        tombstones: [Tombstone] = [],
        hookWirings: [HookWiring] = []
    ) {
        self.schemaVersion = schemaVersion
        self.base = base
        self.categories = categories
        self.sharedComponents = sharedComponents
        self.templates = templates
        self.tombstones = tombstones
        self.hookWirings = hookWirings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else {
            throw TemplateArchiveManifestError.newerSchema(
                found: version, supported: Self.currentSchemaVersion)
        }
        schemaVersion = version
        base = try container.decodeIfPresent(BaseTemplate.self, forKey: .base)
        categories =
            try container.decodeIfPresent([TemplateCategory].self, forKey: .categories) ?? []
        sharedComponents =
            try container.decodeIfPresent([SharedComponent].self, forKey: .sharedComponents) ?? []
        templates =
            try container.decodeIfPresent([TemplateDescriptor].self, forKey: .templates) ?? []
        tombstones = try container.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
        hookWirings = try container.decodeIfPresent([HookWiring].self, forKey: .hookWirings) ?? []
    }
}
