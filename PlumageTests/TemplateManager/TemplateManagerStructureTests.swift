import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel category editing")
struct TemplateManagerStructureTests {
    private func makeModel() -> (model: TemplateManagerModel, manifest: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMStruct-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bundled = base.appending(path: "bundled", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try? fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        let manifest = base.appending(path: "template-manifest.json")
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: manifest),
            overrides: ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json")
        )
        return (model, manifest, { try? fm.removeItem(at: base) })
    }

    @Test("Adding a category persists and enters inline rename")
    func addCategoryPersists() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let before = ctx.model.catalog.categories.count

        ctx.model.beginAddCategory()

        #expect(ctx.model.catalog.categories.count == before + 1)
        #expect(ctx.model.categoryRename != nil)
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().categories.count == before + 1)
    }

    @Test("Committing a rename writes the new name to disk")
    func renamePersists() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.beginAddCategory()
        let id = try #require(ctx.model.categoryRename?.id)

        ctx.model.categoryRename?.name = "Renamed"
        ctx.model.commitCategoryRename()

        #expect(ctx.model.catalog.category(id: id)?.name == "Renamed")
        #expect(ctx.model.categoryRename == nil)
        #expect(
            TemplateCatalogStore(manifestURL: ctx.manifest).load().category(id: id)?.name == "Renamed")
    }

    @Test("Deleting a non-empty category is blocked with an error and no change")
    func deleteNonEmptyBlocked() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let nonEmpty = try #require(
            ctx.model.catalog.sortedCategories.first {
                !ctx.model.catalog.templates(inCategory: $0.id).isEmpty
            })

        ctx.model.deleteCategory(id: nonEmpty.id)

        #expect(ctx.model.catalog.category(id: nonEmpty.id) != nil)
        #expect(ctx.model.structuralError != nil)
    }

    @Test("Deleting an empty category persists")
    func deleteEmptyPersists() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.beginAddCategory()
        let id = try #require(ctx.model.categoryRename?.id)
        ctx.model.cancelCategoryRename()

        ctx.model.deleteCategory(id: id)

        #expect(ctx.model.catalog.category(id: id) == nil)
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().category(id: id) == nil)
    }

    @Test("Moving a template to another category persists")
    func moveTemplatePersists() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let template = try #require(ctx.model.catalog.templates.first)
        let destination = try #require(
            ctx.model.catalog.sortedCategories.first { $0.id != template.categoryID })

        ctx.model.moveTemplate(id: template.id, toCategory: destination.id)

        #expect(ctx.model.catalog.template(id: template.id)?.categoryID == destination.id)
        #expect(
            TemplateCatalogStore(manifestURL: ctx.manifest)
                .load().template(id: template.id)?.categoryID == destination.id)
    }

    @Test("Reordering a category persists the new order")
    func reorderPersists() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let first = try #require(ctx.model.catalog.sortedCategories.first?.id)

        ctx.model.moveCategory(id: first, by: 1)

        #expect(ctx.model.catalog.sortedCategories.first?.id != first)
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().sortedCategories.first?.id != first)
    }
}
