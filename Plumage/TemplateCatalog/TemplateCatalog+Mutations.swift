import Foundation

// The seed for a new custom template: a minimal template (Base + its own empty
// layer) or a copy of an existing one (its scaffold settings + memberships).
nonisolated enum TemplateStartingPoint: Hashable, Sendable {
    case empty
    case copy(String)
}

// Structural mutations on the resolved catalog. They are plain value edits — no
// tombstone bookkeeping here; the persisted overlay derives additions, overrides
// and tombstones by diffing against the bundled default at save time
// (`overlayManifest`). "Predefined" means an id present in the bundled default;
// deleting such an item simply removes it from the resolved value and the diff
// turns that into a tombstone, while restoring re-inserts the bundled record.
nonisolated extension TemplateCatalog {
    // MARK: - Predefined classification

    func isPredefinedCategory(_ id: String) -> Bool {
        TemplateCatalog.bundledDefault.category(id: id) != nil
    }

    func isPredefinedTemplate(_ id: String) -> Bool {
        TemplateCatalog.bundledDefault.template(id: id) != nil
    }

    func isPredefinedSharedComponent(_ id: String) -> Bool {
        TemplateCatalog.bundledDefault.sharedComponent(id: id) != nil
    }

    // MARK: - Category CRUD

    // Adds a category with a collision-free id and display name, appended last.
    @discardableResult
    mutating func addCategory(name: String) -> TemplateCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = uniqueCategoryName(trimmed.isEmpty ? "New Category" : trimmed)
        let id = uniqueCategoryID(slug(displayName, fallback: "category"))
        let order = (categories.map(\.order).max() ?? -1) + 1
        let category = TemplateCategory(id: id, name: displayName, order: order)
        categories.append(category)
        return category
    }

    mutating func renameCategory(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = categories.firstIndex(where: { $0.id == id }) else { return }
        guard categories[index].name != trimmed else { return }
        let resolved = uniqueCategoryName(trimmed, excludingID: id)
        categories[index] = TemplateCategory(id: id, name: resolved, order: categories[index].order)
    }

    // Removes the category. Callers must relocate or remove its templates first
    // (the "delete a non-empty category" edge case is enforced at the model layer).
    mutating func deleteCategory(id: String) {
        categories.removeAll { $0.id == id }
    }

    // Reorders categories to match `orderedIDs`, renumbering `order` 0…n so the
    // overlay diff captures every moved item and no two collide. Ids not listed
    // keep their relative order after the listed ones.
    mutating func reorderCategories(_ orderedIDs: [String]) {
        renumber(&categories, orderedIDs: orderedIDs, id: \.id) { item, order in
            TemplateCategory(id: item.id, name: item.name, order: order)
        }
    }

    // MARK: - Template authoring

    // Adds a custom (`predefined: false`) template with its own layer file named
    // after its id (`templates/<id>.md`, written to the override store by the
    // model). `.copy` seeds the descriptor's scaffold settings from the source and
    // replicates its shared-component memberships; `.empty` is a minimal template
    // (Base + its own layer). Returns the created descriptor (the model needs its id
    // to write the layer file and any imported image).
    @discardableResult
    mutating func addTemplate(
        name: String, image: TemplateImage, categoryID: String,
        startingFrom: TemplateStartingPoint
    ) -> TemplateDescriptor {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = uniqueTemplateName(trimmed.isEmpty ? "New Template" : trimmed)
        let id = uniqueTemplateID(slug(displayName, fallback: "template"))
        let order = (templates.filter { $0.categoryID == categoryID }.map(\.order).max() ?? -1) + 1
        let source: TemplateDescriptor? = {
            if case .copy(let sourceID) = startingFrom { return template(id: sourceID) }
            return nil
        }()
        let descriptor = TemplateDescriptor(
            id: id, name: displayName, image: image, categoryID: categoryID,
            predefined: false, order: order,
            templateLayers: [id],
            gitignoreTags: source?.gitignoreTags ?? [],
            mcpServers: source?.mcpServers ?? [],
            gateCommands: source?.gateCommands ?? .none,
            stackSummary: source?.stackSummary ?? "",
            xcodeMcpLine: source?.xcodeMcpLine ?? ""
        )
        templates.append(descriptor)
        if let source {
            for index in sharedComponents.indices where sharedComponents[index].isMember(source.id) {
                sharedComponents[index].memberTemplateIDs.insert(id)
            }
        }
        return descriptor
    }

    // Enables or disables a template (the Settings → Templates toggle). A disabled
    // predefined template is captured by the overlay diff (it differs from its
    // bundled, enabled record); re-enabling drops it from the overlay again.
    mutating func setTemplateEnabled(id: String, _ enabled: Bool) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].enabled = enabled
    }

    // Removes a template and drops it from every shared component's membership.
    // (A predefined removal becomes a tombstone via the overlay diff; a custom one
    // vanishes outright — the model also trashes its override files.)
    mutating func deleteTemplate(id: String) {
        templates.removeAll { $0.id == id }
        for index in sharedComponents.indices {
            sharedComponents[index].memberTemplateIDs.remove(id)
        }
    }

    private func uniqueTemplateID(_ base: String) -> String {
        let taken = Set(templates.map(\.id)).union(TemplateCatalog.bundledDefault.templates.map(\.id))
        return uniqueValue(base, taken: taken)
    }

    private func uniqueTemplateName(_ base: String) -> String {
        uniqueValue(base, taken: Set(templates.map(\.name)), separator: " ")
    }

    // MARK: - Shared components

    // Adds a custom shared component with its own file named after its id (the model
    // writes a starter to the override store). `.layer`/`.hook`/`.skill`/`.config`
    // resolve to their own override path.
    @discardableResult
    mutating func addSharedComponent(
        name: String, kind: SharedComponentKind, memberTemplateIDs: Set<String>
    ) -> SharedComponent {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = uniqueComponentName(trimmed.isEmpty ? "New Component" : trimmed)
        let id = uniqueComponentID(slug(displayName, fallback: "component"))
        let order = (sharedComponents.map(\.order).max() ?? -1) + 1
        let component = SharedComponent(
            id: id, name: displayName, kind: kind, files: [id], order: order,
            memberTemplateIDs: memberTemplateIDs)
        sharedComponents.append(component)
        return component
    }

    mutating func deleteSharedComponent(id: String) {
        sharedComponents.removeAll { $0.id == id }
    }

    mutating func renameSharedComponent(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sharedComponents.firstIndex(where: { $0.id == id }),
            sharedComponents[index].name != trimmed
        else { return }
        sharedComponents[index].name = uniqueComponentName(trimmed, excludingID: id)
    }

    // Sets one template's membership in a component (the checklist toggle).
    mutating func setMembership(componentID: String, templateID: String, isMember: Bool) {
        guard let index = sharedComponents.firstIndex(where: { $0.id == componentID }) else { return }
        if isMember {
            sharedComponents[index].memberTemplateIDs.insert(templateID)
        } else {
            sharedComponents[index].memberTemplateIDs.remove(templateID)
        }
    }

    private func uniqueComponentID(_ base: String) -> String {
        let taken = Set(sharedComponents.map(\.id))
            .union(TemplateCatalog.bundledDefault.sharedComponents.map(\.id))
        return uniqueValue(base, taken: taken)
    }

    private func uniqueComponentName(_ base: String, excludingID: String? = nil) -> String {
        let taken = Set(sharedComponents.filter { $0.id != excludingID }.map(\.name))
        return uniqueValue(base, taken: taken, separator: " ")
    }

    // MARK: - Template placement

    // Moves a template to another category, appended after that category's last
    // template. No-op if the destination is missing or already its category.
    mutating func moveTemplate(id: String, toCategory categoryID: String) {
        guard category(id: categoryID) != nil,
            let index = templates.firstIndex(where: { $0.id == id }),
            templates[index].categoryID != categoryID
        else { return }
        let maxOrder = templates.filter { $0.categoryID == categoryID }.map(\.order).max() ?? -1
        templates[index].categoryID = categoryID
        templates[index].order = maxOrder + 1
    }

    // Renumbers `order` 0…n for the templates of one category to match `orderedIDs`.
    // Templates in other categories are untouched (orders are per-category).
    mutating func reorderTemplates(inCategory categoryID: String, orderedIDs: [String]) {
        let positions = Dictionary(
            orderedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        for index in templates.indices where templates[index].categoryID == categoryID {
            if let position = positions[templates[index].id] {
                templates[index].order = position
            }
        }
    }

    // MARK: - Restore

    // Bundled predefined items currently missing from the resolved catalog — i.e.
    // the ones a user deleted, offered for per-item restore. Custom items never
    // appear here (they have no bundled origin).
    func deletedPredefinedItems() -> [(kind: TombstoneKind, id: String, name: String)] {
        let bundled = TemplateCatalog.bundledDefault
        var items: [(TombstoneKind, String, String)] = []
        items += bundled.categories
            .filter { category(id: $0.id) == nil }
            .map { (.category, $0.id, $0.name) }
        items += bundled.sharedComponents
            .filter { sharedComponent(id: $0.id) == nil }
            .map { (.sharedComponent, $0.id, $0.name) }
        items += bundled.templates
            .filter { template(id: $0.id) == nil }
            .map { (.template, $0.id, $0.name) }
        return items
    }

    // Re-inserts a deleted predefined item from the bundled default. Restore is
    // transitive for a template's container: a restored template re-creates its
    // category if that too was deleted, and rejoins the shared components the
    // bundled default placed it in.
    mutating func restore(_ kind: TombstoneKind, id: String) {
        let bundled = TemplateCatalog.bundledDefault
        switch kind {
        case .category:
            guard category(id: id) == nil, let category = bundled.category(id: id) else { return }
            categories.append(category)
        case .sharedComponent:
            guard sharedComponent(id: id) == nil,
                let component = bundled.sharedComponent(id: id)
            else { return }
            sharedComponents.append(component)
        case .template:
            guard template(id: id) == nil, let template = bundled.template(id: id) else { return }
            templates.append(template)
            if category(id: template.categoryID) == nil,
                let category = bundled.category(id: template.categoryID)
            {
                categories.append(category)
            }
            for index in sharedComponents.indices
            where bundled.sharedComponent(id: sharedComponents[index].id)?.isMember(id) == true {
                sharedComponents[index].memberTemplateIDs.insert(id)
            }
        }
    }

    // MARK: - Naming helpers

    private func uniqueCategoryID(_ base: String) -> String {
        let taken = Set(categories.map(\.id)).union(TemplateCatalog.bundledDefault.categories.map(\.id))
        return uniqueValue(base, taken: taken)
    }

    private func uniqueCategoryName(_ base: String, excludingID: String? = nil) -> String {
        let taken = Set(categories.filter { $0.id != excludingID }.map(\.name))
        return uniqueValue(base, taken: taken, separator: " ")
    }
}

// MARK: - Shared structural helpers

nonisolated extension TemplateCatalog {
    // Suffix-walks `base` until it misses `taken` ("name", "name-2", "name-3"…).
    func uniqueValue(_ base: String, taken: Set<String>, separator: String = "-") -> String {
        guard taken.contains(base) else { return base }
        var suffix = 2
        while taken.contains("\(base)\(separator)\(suffix)") { suffix += 1 }
        return "\(base)\(separator)\(suffix)"
    }

    // Lowercased, hyphen-joined, alphanumeric slug; `fallback` when nothing remains.
    func slug(_ text: String, fallback: String) -> String {
        let lowered = text.lowercased()
        var pieces: [String] = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        let joined = pieces.joined(separator: "-")
        return joined.isEmpty ? fallback : joined
    }

    // Applies the `orderedIDs` permutation and renumbers `order` 0…n. Items whose
    // id is absent from `orderedIDs` are appended in their existing order.
    func renumber<Item>(
        _ items: inout [Item], orderedIDs: [String], id: (Item) -> String,
        rebuild: (Item, Int) -> Item
    ) {
        let byID = Dictionary(items.map { (id($0), $0) }, uniquingKeysWith: { _, last in last })
        var ordered: [Item] = orderedIDs.compactMap { byID[$0] }
        let listed = Set(orderedIDs)
        ordered += items.filter { !listed.contains(id($0)) }
        items = ordered.enumerated().map { index, item in rebuild(item, index) }
    }
}
