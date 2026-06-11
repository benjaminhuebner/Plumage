import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManagerModel archive import entry (integration)", .tags(.integration))
struct TemplateManagerArchiveImportTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "manager-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "bundled"), withIntermediateDirectories: true)
        return root
    }

    private func makeModel(_ root: URL) -> TemplateManagerModel {
        TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: root.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(
                bundledRoot: root.appending(path: "bundled"),
                overrideRoot: root.appending(path: "override")),
            hookWiringStoreURL: root.appending(path: "hook-wirings.json")
        )
    }

    @Test("A readable archive raises the pending import with all items preselected")
    func validArchiveRaisesPendingImport() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var catalog = TemplateCatalog.bundledDefault
        catalog.templates.append(
            TemplateDescriptor(
                id: "my-temp", name: "My Temp", image: .symbol("star"),
                categoryID: catalog.sortedCategories[0].id, predefined: false, order: 99,
                templateLayers: ["my-temp"], gitignoreTags: [], mcpServers: [],
                gateCommands: .xcode, stackSummary: "", xcodeMcpLine: ""))
        let archive = root.appending(path: "export.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: catalog,
            overrides: ScaffoldOverrides(
                bundledRoot: root.appending(path: "bundled"),
                overrideRoot: root.appending(path: "override")),
            hookWirings: HookWiringStore()
        ).export(.template("my-temp"), to: archive)

        let model = makeModel(root)
        await model.beginImport(fromArchive: archive)

        let pending = try #require(model.pendingImport)
        defer { pending.cleanup() }
        #expect(pending.items.map(\.id) == ["template:my-temp"])
        #expect(model.pendingImportSelection == ["template:my-temp"])
        #expect(model.structuralError == nil)
    }

    @Test("Exporting through the model writes a readable archive")
    func modelExportWritesArchive() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root)
        await model.load()

        let destination = root.appending(path: "all.plumagetemplates")
        await model.export(.fullCatalog, to: destination)

        #expect(model.structuralError == nil)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(
            model.exportSuggestedFileName(for: .fullCatalog)
                == "Plumage Templates.plumagetemplates")
    }

    @Test("Confirming the import applies the selection and clears the pending state")
    func confirmImportApplies() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var catalog = TemplateCatalog.bundledDefault
        catalog.templates.append(
            TemplateDescriptor(
                id: "my-temp", name: "My Temp", image: .symbol("star"),
                categoryID: catalog.sortedCategories[0].id, predefined: false, order: 99,
                templateLayers: ["my-temp"], gitignoreTags: [], mcpServers: [],
                gateCommands: .xcode, stackSummary: "", xcodeMcpLine: ""))
        let sourceOverrides = ScaffoldOverrides(
            bundledRoot: root.appending(path: "bundled"),
            overrideRoot: root.appending(path: "source-override"))
        try sourceOverrides.writeOverride("layer", toRelative: "templates/my-temp/CLAUDE.md")
        let archive = root.appending(path: "export.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: catalog, overrides: sourceOverrides, hookWirings: HookWiringStore()
        ).export(.template("my-temp"), to: archive)

        let model = makeModel(root)
        await model.beginImport(fromArchive: archive)
        let staging = try #require(model.pendingImport).stagingDir
        model.confirmImport()

        #expect(model.pendingImport == nil)
        #expect(model.catalog.template(id: "my-temp")?.name == "My Temp")
        #expect(model.overrides.hasOverride(forRelative: "templates/my-temp/CLAUDE.md"))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(model.structuralError == nil)
    }

    @Test("Cancelling the import removes the staging dir and changes nothing")
    func cancelImportCleansUp() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "export.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: .bundledDefault,
            overrides: ScaffoldOverrides(
                bundledRoot: root.appending(path: "bundled"),
                overrideRoot: root.appending(path: "override")),
            hookWirings: HookWiringStore()
        ).export(.fullCatalog, to: archive)

        let model = makeModel(root)
        await model.beginImport(fromArchive: archive)
        let staging = try #require(model.pendingImport).stagingDir
        let catalogBefore = model.catalog
        model.cancelImport()

        #expect(model.pendingImport == nil)
        #expect(model.pendingImportSelection.isEmpty)
        #expect(model.catalog == catalogBefore)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("A dropped archive routes to the import flow instead of file copy")
    func droppedArchiveRoutesToImport() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "export.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: .bundledDefault,
            overrides: ScaffoldOverrides(
                bundledRoot: root.appending(path: "bundled"),
                overrideRoot: root.appending(path: "source-override")),
            hookWirings: HookWiringStore()
        ).export(.fullCatalog, to: archive)

        let model = makeModel(root)
        await model.load()
        let accepted = model.importDropped(urls: [archive])
        #expect(accepted)
        await model.archiveImportTask?.value

        let pending = try #require(model.pendingImport)
        defer { pending.cleanup() }
        #expect(!pending.items.isEmpty)
        // The archive must not have been copied into the store as a plain file.
        #expect(model.overrides.overrideFileNamesRecursive(inRelativeDir: "").isEmpty)
    }

    @Test("An unreadable file shows the error banner and raises no sheet")
    func corruptArchiveShowsBanner() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let garbage = root.appending(path: "garbage.plumagetemplates")
        try Data("nope".utf8).write(to: garbage)

        let model = makeModel(root)
        await model.beginImport(fromArchive: garbage)

        #expect(model.pendingImport == nil)
        #expect(model.structuralError != nil)
    }
}
