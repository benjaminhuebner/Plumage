import Foundation

// The resolved catalog: all three tiers in memory, ready to query and resolve.
// The store builds it from `manifest ?? bundledDefault`. Queries return entries
// sorted by their `order` so callers (and the UI) get a deterministic layout.
nonisolated struct TemplateCatalog: Codable, Hashable, Sendable {
    let base: BaseTemplate
    let categories: [TemplateCategory]
    let sharedComponents: [SharedComponent]
    let templates: [TemplateDescriptor]

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

    init(manifest: TemplateManifest) {
        self.init(
            base: manifest.base,
            categories: manifest.categories,
            sharedComponents: manifest.sharedComponents,
            templates: manifest.templates
        )
    }

    var manifest: TemplateManifest {
        TemplateManifest(
            schemaVersion: TemplateManifest.currentSchemaVersion,
            base: base,
            categories: categories,
            sharedComponents: sharedComponents,
            templates: templates
        )
    }

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
