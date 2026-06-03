import Foundation

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
