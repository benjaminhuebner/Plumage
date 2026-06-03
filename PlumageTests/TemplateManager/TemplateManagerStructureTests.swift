import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel category editing")
struct TemplateManagerStructureTests {
    private func makeModel() -> (
        model: TemplateManagerModel, manifest: URL, override: URL, cleanup: () -> Void
    ) {
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
        return (model, manifest, override, { try? fm.removeItem(at: base) })
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

    // MARK: - Template authoring

    @Test("Authoring a symbol template persists, writes its layer file, and selects it")
    func addTemplateSymbol() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let category = try #require(ctx.model.catalog.sortedCategories.first)

        let ok = ctx.model.addTemplate(
            NewTemplateRequest(
                name: "Authored", imageChoice: .symbol("star"),
                categoryID: category.id, startingPoint: .empty))

        #expect(ok)
        let created = try #require(ctx.model.catalog.templates.first { $0.name == "Authored" })
        #expect(ctx.model.selection == .template(created.id))
        let layerURL = ctx.override.appending(path: "templates/\(created.id)/CLAUDE.md")
        #expect(FileManager.default.fileExists(atPath: layerURL.path))
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().template(id: created.id) != nil)
    }

    @Test("Authoring with an imported image copies the file and stores a .file image")
    func addTemplateImportedImage() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let category = try #require(ctx.model.catalog.sortedCategories.first)
        let source = FileManager.default.temporaryDirectory
            .appending(path: "import-\(UUID().uuidString).png")
        try Data([0x1, 0x2, 0x3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let ok = ctx.model.addTemplate(
            NewTemplateRequest(
                name: "Imaged", imageChoice: .importedFile(source),
                categoryID: category.id, startingPoint: .empty))

        #expect(ok)
        let created = try #require(ctx.model.catalog.templates.first { $0.name == "Imaged" })
        let image = try #require(
            { () -> String? in
                if case .file(let relativePath) = created.image { return relativePath }
                return nil
            }())
        #expect(image.hasPrefix("template-images/\(created.id)"))
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: image).path))
    }

    // MARK: - Shared components & membership

    @Test("Toggling membership persists and changes effective layers")
    func setMembershipPersists() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let other = try #require(ctx.model.catalog.template(id: "other"))

        ctx.model.setMembership(componentID: "swift-shared", templateID: other.id, isMember: true)

        #expect(ctx.model.catalog.effectiveLayers(forTemplate: other.id).contains("swift-shared"))
        #expect(
            TemplateCatalogStore(manifestURL: ctx.manifest)
                .load().sharedComponent(id: "swift-shared")?.isMember(other.id) == true)
    }

    @Test("Authoring a shared component persists, writes its file, and selects it")
    func addSharedComponentModel() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }

        let ok = ctx.model.addSharedComponent(
            NewSharedComponentRequest(name: "Extra Layer", kind: .layer, memberTemplateIDs: []))

        #expect(ok)
        let created = try #require(
            ctx.model.catalog.sharedComponents.first { $0.name == "Extra Layer" })
        #expect(ctx.model.selection == .sharedComponent(created.id))
        let fileURL = ctx.override.appending(path: "templates/\(created.id)/CLAUDE.md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Deleting a user shared component removes it after confirmation")
    func deleteSharedComponentModel() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        _ = ctx.model.addSharedComponent(
            NewSharedComponentRequest(name: "Doomed", kind: .layer, memberTemplateIDs: []))
        let created = try #require(ctx.model.catalog.sharedComponents.first { $0.name == "Doomed" })

        ctx.model.requestDeleteSharedComponent(id: created.id)
        #expect(ctx.model.pendingComponentDeletion?.id == created.id)
        ctx.model.confirmDeleteSharedComponent()

        #expect(ctx.model.catalog.sharedComponent(id: created.id) == nil)
        #expect(
            TemplateCatalogStore(manifestURL: ctx.manifest).load().sharedComponent(id: created.id)
                == nil)
    }

    // MARK: - Delete predefined & restore

    @Test("Deleting a predefined template tombstones it; restore brings it back")
    func deleteRestorePredefinedTemplate() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let template = try #require(ctx.model.catalog.templates.first { $0.predefined })

        ctx.model.deleteTemplate(id: template.id)
        #expect(ctx.model.catalog.template(id: template.id) == nil)
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().template(id: template.id) == nil)

        let item = try #require(ctx.model.restorableItems.first { $0.itemID == template.id })
        ctx.model.restore(item)
        #expect(ctx.model.catalog.template(id: template.id) != nil)
        #expect(TemplateCatalogStore(manifestURL: ctx.manifest).load().template(id: template.id) != nil)
    }

    @Test("Deleting a custom template asks for confirmation, then removes it")
    func deleteCustomTemplateConfirms() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let category = try #require(ctx.model.catalog.sortedCategories.first)
        _ = ctx.model.addTemplate(
            NewTemplateRequest(
                name: "Throwaway", imageChoice: .symbol("doc"),
                categoryID: category.id, startingPoint: .empty))
        let created = try #require(ctx.model.catalog.templates.first { $0.name == "Throwaway" })

        ctx.model.deleteTemplate(id: created.id)
        #expect(ctx.model.pendingTemplateDeletion?.id == created.id)
        #expect(ctx.model.catalog.template(id: created.id) != nil)

        ctx.model.confirmDeleteTemplate()
        #expect(ctx.model.catalog.template(id: created.id) == nil)
    }

    @Test("Restore Defaults clears custom items and tombstones but keeps file overrides")
    func restoreAllDefaultsKeepsFileOverrides() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        _ = try ctx.model.overrides.writeOverride("EDITED", toRelative: "templates/CLAUDE.md")
        let category = try #require(ctx.model.catalog.sortedCategories.first)
        _ = ctx.model.addTemplate(
            NewTemplateRequest(
                name: "Custom", imageChoice: .symbol("doc"),
                categoryID: category.id, startingPoint: .empty))
        let predefined = try #require(ctx.model.catalog.templates.first { $0.predefined })
        ctx.model.deleteTemplate(id: predefined.id)
        #expect(ctx.model.catalog != .bundledDefault)

        ctx.model.restoreAllDefaults()

        #expect(ctx.model.catalog == .bundledDefault)
        #expect(!ctx.model.catalog.templates.contains { $0.name == "Custom" })
        #expect(ctx.model.overrides.hasOverride(forRelative: "templates/CLAUDE.md"))
    }
}
