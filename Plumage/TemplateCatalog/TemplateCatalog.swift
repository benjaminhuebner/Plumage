import Foundation

// The resolved catalog: all three tiers in memory, ready to query and resolve.
// The store builds it by merging the persisted overlay manifest onto the bundled
// default (additions/overrides upserted by id, tombstoned predefined items
// subtracted). Mutations edit this value directly; persistence re-derives the
// minimal overlay by diffing against the bundled default (`overlayManifest`).
// Queries return entries sorted by their `order` so the UI gets a deterministic
// layout.
nonisolated struct TemplateCatalog: Codable, Hashable, Sendable {
    var base: BaseTemplate
    var categories: [TemplateCategory]
    var sharedComponents: [SharedComponent]
    var templates: [TemplateDescriptor]

    init(
        base: BaseTemplate,
        categories: [TemplateCategory],
        sharedComponents: [SharedComponent],
        templates: [TemplateDescriptor]
    ) {
        self.base = base
        self.categories = categories
        self.sharedComponents = sharedComponents
        self.templates = templates
    }

    // Resolve a stored overlay onto a baseline. An overlay entry whose id matches
    // a baseline item overrides it; a new id adds it; a tombstoned id drops the
    // baseline item. Baseline items the overlay never mentions pass through
    // unchanged — so predefined items shipped in a later app version still appear.
    init(manifest: TemplateManifest, bundled: TemplateCatalog = .bundledDefault) {
        let deadCategories = manifest.tombstonedIDs(.category)
        let deadComponents = manifest.tombstonedIDs(.sharedComponent)
        let deadTemplates = manifest.tombstonedIDs(.template)

        self.base = manifest.base
        self.categories = Self.merge(
            baseline: bundled.categories, overlay: manifest.categories,
            dead: deadCategories, id: \.id)
        self.sharedComponents = Self.merge(
            baseline: bundled.sharedComponents, overlay: manifest.sharedComponents,
            dead: deadComponents, id: \.id)
        self.templates = Self.merge(
            baseline: bundled.templates, overlay: manifest.templates,
            dead: deadTemplates, id: \.id)
    }

    private static func merge<Item>(
        baseline: [Item], overlay: [Item], dead: Set<String>, id: (Item) -> String
    ) -> [Item] {
        let overlayByID = Dictionary(overlay.map { (id($0), $0) }, uniquingKeysWith: { _, last in last })
        var result =
            baseline
            .filter { !dead.contains(id($0)) }
            .map { overlayByID[id($0)] ?? $0 }
        let baselineIDs = Set(baseline.map(id))
        result += overlay.filter { !baselineIDs.contains(id($0)) }
        return result
    }

    // The minimal overlay manifest that reproduces this catalog when merged back
    // onto `bundled`: items equal to their bundled counterpart are omitted; changed
    // or new items are written; bundled items absent here become tombstones.
    func overlayManifest(bundled: TemplateCatalog = .bundledDefault) -> TemplateManifest {
        var tombstones: [Tombstone] = []
        tombstones += Self.tombstones(
            kind: .category, baseline: bundled.categories, resolved: categories, id: \.id)
        tombstones += Self.tombstones(
            kind: .sharedComponent, baseline: bundled.sharedComponents,
            resolved: sharedComponents, id: \.id)
        tombstones += Self.tombstones(
            kind: .template, baseline: bundled.templates, resolved: templates, id: \.id)

        return TemplateManifest(
            schemaVersion: TemplateManifest.currentSchemaVersion,
            base: base,
            categories: Self.changedOrNew(resolved: categories, baseline: bundled.categories, id: \.id),
            sharedComponents: Self.changedOrNew(
                resolved: sharedComponents, baseline: bundled.sharedComponents, id: \.id),
            templates: Self.changedOrNew(resolved: templates, baseline: bundled.templates, id: \.id),
            tombstones: tombstones
        )
    }

    private static func changedOrNew<Item: Equatable>(
        resolved: [Item], baseline: [Item], id: (Item) -> String
    ) -> [Item] {
        let baselineByID = Dictionary(baseline.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        return resolved.filter { baselineByID[id($0)] != $0 }
    }

    private static func tombstones<Item>(
        kind: TombstoneKind, baseline: [Item], resolved: [Item], id: (Item) -> String
    ) -> [Tombstone] {
        let resolvedIDs = Set(resolved.map(id))
        return
            baseline
            .map(id)
            .filter { !resolvedIDs.contains($0) }
            .sorted()
            .map { Tombstone(kind: kind, id: $0) }
    }

    // Convenience for callers that persist or round-trip via the standard bundled
    // baseline (the store, tests).
    var manifest: TemplateManifest { overlayManifest() }

    // MARK: - Lookups

    func template(id: String) -> TemplateDescriptor? { templates.first { $0.id == id } }
    func sharedComponent(id: String) -> SharedComponent? { sharedComponents.first { $0.id == id } }
    func category(id: String) -> TemplateCategory? { categories.first { $0.id == id } }

    // MARK: - Ordered views

    var sortedCategories: [TemplateCategory] { categories.sorted { $0.order < $1.order } }
    var sortedSharedComponents: [SharedComponent] { sharedComponents.sorted { $0.order < $1.order } }

    func templates(inCategory categoryID: String) -> [TemplateDescriptor] {
        templates.filter { $0.categoryID == categoryID }.sorted { $0.order < $1.order }
    }

    // Shared components a template is a member of, in concatenation order.
    func sharedComponents(forTemplate templateID: String) -> [SharedComponent] {
        sharedComponents.filter { $0.isMember(templateID) }.sorted { $0.order < $1.order }
    }

    // Templates that include a given shared component, in display order.
    func templates(memberOf componentID: String) -> [TemplateDescriptor] {
        guard let component = sharedComponent(id: componentID) else { return [] }
        return templates.filter { component.isMember($0.id) }.sorted { $0.order < $1.order }
    }
}

nonisolated extension TemplateManifest {
    func tombstonedIDs(_ kind: TombstoneKind) -> Set<String> {
        Set(tombstones.filter { $0.kind == kind }.map(\.id))
    }
}
