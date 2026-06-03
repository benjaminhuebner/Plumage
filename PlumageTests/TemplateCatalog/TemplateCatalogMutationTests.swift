import Foundation
import Testing

@testable import Plumage

@Suite("TemplateCatalog structural mutations + overlay round-trip")
struct TemplateCatalogMutationTests {
    private func tempManifestURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "tmpl-\(UUID().uuidString).json")
    }

    // MARK: - Category CRUD

    @Test("addCategory appends a uniquely-id'd, uniquely-named category")
    func addCategory() {
        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "My Stuff")
        #expect(created.id == "my-stuff")
        #expect(catalog.category(id: created.id)?.name == "My Stuff")
        #expect(catalog.sortedCategories.last?.id == created.id)
    }

    @Test("addCategory suffix-walks colliding names and ids")
    func addCategoryCollision() {
        var catalog = TemplateCatalog.bundledDefault
        let first = catalog.addCategory(name: "Tools")
        let second = catalog.addCategory(name: "Tools")
        #expect(first.name == "Tools")
        #expect(second.name == "Tools 2")
        #expect(first.id != second.id)
    }

    @Test("addCategory falls back to a default name and id when blank")
    func addCategoryBlank() {
        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "   ")
        #expect(created.name == "New Category")
        #expect(!created.id.isEmpty)
    }

    @Test("renameCategory changes the name, keeps id and order")
    func renameCategory() {
        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "Old")
        catalog.renameCategory(id: created.id, to: "New Name")
        #expect(catalog.category(id: created.id)?.name == "New Name")
        #expect(catalog.category(id: created.id)?.order == created.order)
    }

    @Test("renameCategory to blank is ignored")
    func renameBlankIgnored() {
        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "Keep")
        catalog.renameCategory(id: created.id, to: "   ")
        #expect(catalog.category(id: created.id)?.name == "Keep")
    }

    @Test("reorderCategories renumbers order to match the given id order")
    func reorderCategories() {
        var catalog = TemplateCatalog.bundledDefault
        let reversed = Array(catalog.sortedCategories.map(\.id).reversed())
        catalog.reorderCategories(reversed)
        #expect(catalog.sortedCategories.map(\.id) == reversed)
        #expect(catalog.sortedCategories.map(\.order) == Array(0..<reversed.count))
    }

    // MARK: - Tombstone / overlay resolution

    @Test("Deleting a custom category leaves no tombstone (gone outright)")
    func deleteCustomNoTombstone() {
        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "Temp")
        catalog.deleteCategory(id: created.id)
        #expect(catalog.category(id: created.id) == nil)
        #expect(!catalog.overlayManifest().tombstones.contains { $0.id == created.id })
    }

    @Test("Deleting a predefined category records a tombstone that survives a round-trip")
    func deletePredefinedTombstone() throws {
        var catalog = TemplateCatalog.bundledDefault
        let victim = try #require(catalog.sortedCategories.first)
        catalog.deleteCategory(id: victim.id)

        let overlay = catalog.overlayManifest()
        #expect(overlay.tombstones.contains { $0.kind == .category && $0.id == victim.id })
        #expect(TemplateCatalog(manifest: overlay).category(id: victim.id) == nil)
    }

    @Test("Restoring a deleted predefined category re-adds the bundled record")
    func restorePredefined() throws {
        var catalog = TemplateCatalog.bundledDefault
        let victim = try #require(catalog.sortedCategories.first)
        catalog.deleteCategory(id: victim.id)
        catalog.categories.append(try #require(TemplateCatalog.bundledDefault.category(id: victim.id)))

        let overlay = catalog.overlayManifest()
        #expect(!overlay.tombstones.contains { $0.id == victim.id })
        #expect(TemplateCatalog(manifest: overlay).category(id: victim.id) != nil)
    }

    @Test("Overlay omits unchanged bundled items (minimal manifest)")
    func overlayMinimal() {
        let overlay = TemplateCatalog.bundledDefault.overlayManifest()
        #expect(overlay.categories.isEmpty)
        #expect(overlay.templates.isEmpty)
        #expect(overlay.sharedComponents.isEmpty)
        #expect(overlay.tombstones.isEmpty)
    }

    @Test("A later-shipped bundled item passes through an old overlay")
    func futureBundledItemAppears() {
        // An overlay authored against a smaller baseline must not hide items the
        // current bundled default adds (merge passes untouched baseline through).
        var smallBundled = TemplateCatalog.bundledDefault
        let extra = smallBundled.addCategory(name: "User Added")
        let overlay = smallBundled.overlayManifest()

        let merged = TemplateCatalog(manifest: overlay, bundled: .bundledDefault)
        #expect(merged.category(id: extra.id) != nil)
        for category in TemplateCatalog.bundledDefault.categories {
            #expect(merged.category(id: category.id) != nil)
        }
    }

    // MARK: - Template placement

    @Test("moveTemplate changes the category and appends the template last")
    func moveTemplate() throws {
        var catalog = TemplateCatalog.bundledDefault
        let template = try #require(catalog.templates.first)
        let destination = try #require(
            catalog.sortedCategories.first { $0.id != template.categoryID })

        catalog.moveTemplate(id: template.id, toCategory: destination.id)

        #expect(catalog.template(id: template.id)?.categoryID == destination.id)
        #expect(catalog.templates(inCategory: destination.id).last?.id == template.id)
    }

    @Test("moveTemplate to the current category is a no-op")
    func moveTemplateSameCategory() throws {
        var catalog = TemplateCatalog.bundledDefault
        let template = try #require(catalog.templates.first)
        let before = catalog
        catalog.moveTemplate(id: template.id, toCategory: template.categoryID)
        #expect(catalog == before)
    }

    @Test("moveTemplate survives the overlay round-trip")
    func moveTemplateRoundTrip() throws {
        var catalog = TemplateCatalog.bundledDefault
        let template = try #require(catalog.templates.first)
        let destination = try #require(
            catalog.sortedCategories.first { $0.id != template.categoryID })

        catalog.moveTemplate(id: template.id, toCategory: destination.id)
        let reloaded = TemplateCatalog(manifest: catalog.overlayManifest())

        #expect(reloaded.template(id: template.id)?.categoryID == destination.id)
    }

    @Test("reorderTemplates renumbers within one category only")
    func reorderTemplatesWithinCategory() throws {
        var catalog = TemplateCatalog.bundledDefault
        let category = try #require(
            catalog.sortedCategories.first { catalog.templates(inCategory: $0.id).count >= 2 })
        let reversed = Array(catalog.templates(inCategory: category.id).map(\.id).reversed())

        catalog.reorderTemplates(inCategory: category.id, orderedIDs: reversed)

        #expect(catalog.templates(inCategory: category.id).map(\.id) == reversed)
    }

    // MARK: - Store persistence round-trip

    @Test("save then load round-trips a custom category through the overlay manifest")
    func saveLoadRoundTrip() throws {
        let url = tempManifestURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TemplateCatalogStore(manifestURL: url)

        var catalog = TemplateCatalog.bundledDefault
        let created = catalog.addCategory(name: "Persisted")
        try store.save(catalog)

        let loaded = store.load()
        #expect(loaded.category(id: created.id)?.name == "Persisted")
        #expect(loaded.templates.count == TemplateCatalog.bundledDefault.templates.count)
    }

    @Test("save with a predefined delete then load keeps it deleted")
    func saveDeleteRoundTrip() throws {
        let url = tempManifestURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TemplateCatalogStore(manifestURL: url)

        var catalog = TemplateCatalog.bundledDefault
        let victim = try #require(catalog.sortedCategories.first)
        catalog.deleteCategory(id: victim.id)
        try store.save(catalog)

        #expect(store.load().category(id: victim.id) == nil)
    }

    @Test("reset drops the overlay and returns to the bundled default")
    func resetReturnsBundled() throws {
        let url = tempManifestURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TemplateCatalogStore(manifestURL: url)

        var catalog = TemplateCatalog.bundledDefault
        catalog.addCategory(name: "Gone after reset")
        try store.save(catalog)
        #expect(store.load() != .bundledDefault)

        try store.reset()
        #expect(store.load() == .bundledDefault)
    }

    @Test("save throws without a manifest location")
    func saveWithoutURLThrows() {
        let store = TemplateCatalogStore(manifestURL: nil)
        #expect(throws: TemplateCatalogStoreError.self) {
            try store.save(.bundledDefault)
        }
    }
}
