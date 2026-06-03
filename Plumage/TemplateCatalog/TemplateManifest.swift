import Foundation

// The persisted catalog *overlay*. Absent on a fresh install (the store then uses
// the bundled default). Lives under Application Support, never the Claude config
// directory (CCI boundary stays intact).
//
// Overlay semantics (#00069): the stored arrays are upserts over the bundled
// default — an entry whose id matches a bundled item overrides it, a new id adds
// an item — and `tombstones` subtracts deleted predefined items. The resolved
// catalog is `bundled-default` merged with this overlay (see `TemplateCatalog`).
//
// Forward-compat: unknown keys written by a newer Plumage are ignored on decode;
// a missing `tombstones` key (a #00067-era manifest) decodes to no tombstones.
// A manifest that fails to decode is handled by the store (falls back to bundled).
nonisolated struct TemplateManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let base: BaseTemplate
    let categories: [TemplateCategory]
    let sharedComponents: [SharedComponent]
    let templates: [TemplateDescriptor]
    let tombstones: [Tombstone]

    init(
        schemaVersion: Int,
        base: BaseTemplate,
        categories: [TemplateCategory],
        sharedComponents: [SharedComponent],
        templates: [TemplateDescriptor],
        tombstones: [Tombstone] = []
    ) {
        self.schemaVersion = schemaVersion
        self.base = base
        self.categories = categories
        self.sharedComponents = sharedComponents
        self.templates = templates
        self.tombstones = tombstones
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        base = try container.decode(BaseTemplate.self, forKey: .base)
        categories = try container.decode([TemplateCategory].self, forKey: .categories)
        sharedComponents = try container.decode([SharedComponent].self, forKey: .sharedComponents)
        templates = try container.decode([TemplateDescriptor].self, forKey: .templates)
        tombstones = try container.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
    }
}
