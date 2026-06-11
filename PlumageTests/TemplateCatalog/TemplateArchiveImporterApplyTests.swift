import Foundation
import Testing

@testable import Plumage

@Suite("TemplateArchiveImporter apply side")
struct TemplateArchiveImporterApplyTests {
    private struct Fixture {
        let root: URL
        let overrides: ScaffoldOverrides
        let staging: URL
        let store: TemplateCatalogStore
        let wiringsURL: URL
        var catalog: TemplateCatalog

        func writeLocal(_ relative: String, _ content: String = "x") throws {
            try overrides.writeOverride(Data(content.utf8), toRelative: relative)
        }

        func writeStaged(_ relative: String, _ content: String = "x") throws {
            let url = staging.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }

        func writeManifest(_ manifest: TemplateArchiveManifest) throws {
            try JSONEncoder().encode(manifest).write(
                to: staging.appending(path: TemplateArchiveExporter.manifestFileName))
        }

        func importer() -> TemplateArchiveImporter {
            TemplateArchiveImporter(catalog: catalog, overrides: overrides)
        }

        func localData(_ relative: String) -> Data? {
            overrides.overrideURL(forRelative: relative).flatMap { try? Data(contentsOf: $0) }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-apply-\(UUID().uuidString)")
        let staging = root.appending(path: "staging")
        try FileManager.default.createDirectory(
            at: root.appending(path: "bundled"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            overrides: ScaffoldOverrides(
                bundledRoot: root.appending(path: "bundled"),
                overrideRoot: root.appending(path: "override")),
            staging: staging,
            store: TemplateCatalogStore(manifestURL: root.appending(path: "manifest.json")),
            wiringsURL: root.appending(path: "hook-wirings.json"),
            catalog: .bundledDefault
        )
    }

    private func customTemplate(id: String, categoryID: String) -> TemplateDescriptor {
        TemplateDescriptor(
            id: id, name: id, image: .symbol("star"), categoryID: categoryID, predefined: false,
            order: 99, templateLayers: [id], gitignoreTags: [], mcpServers: [],
            gateCommands: .xcode, stackSummary: "", xcodeMcpLine: "")
    }

    @Test("Applying a selected subset copies files and merges records")
    func selectiveApply() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        let component = SharedComponent(
            id: "my-comp", name: "My Comp",
            files: [ComponentFile(kind: .hook, name: "my-hook")],
            order: 50, memberTemplateIDs: ["my-temp"])
        try fixture.writeManifest(
            TemplateArchiveManifest(sharedComponents: [component], templates: [template]))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md", "layer")
        try fixture.writeStaged("hooks/my-hook.sh", "hook")

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["template:my-temp", "component:my-comp"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )

        #expect(result.catalog.template(id: "my-temp") == template)
        #expect(result.catalog.sharedComponent(id: "my-comp") == component)
        #expect(fixture.localData("templates/my-temp/CLAUDE.md") == Data("layer".utf8))
        #expect(fixture.localData("hooks/my-hook.sh") == Data("hook".utf8))
        let persisted = fixture.store.load()
        #expect(persisted.template(id: "my-temp") == template)
    }

    @Test("An unselected, locally missing member component is dropped silently")
    func droppedMembershipForMissingComponent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        let component = SharedComponent(
            id: "my-comp", name: "My Comp", files: [], order: 50, memberTemplateIDs: ["my-temp"])
        try fixture.writeManifest(
            TemplateArchiveManifest(sharedComponents: [component], templates: [template]))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md")

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["template:my-temp"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )

        #expect(result.catalog.template(id: "my-temp") != nil)
        #expect(result.catalog.sharedComponent(id: "my-comp") == nil)
        #expect(result.catalog.sharedComponents(forTemplate: "my-temp").isEmpty)
    }

    @Test("A selected deletions row removes tombstoned items and their memberships")
    func tombstonesApply() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let victim = try #require(fixture.catalog.templates.first(where: { $0.predefined }))
        try fixture.writeManifest(
            TemplateArchiveManifest(tombstones: [Tombstone(kind: .template, id: victim.id)]))

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["deleted-defaults"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )

        #expect(result.catalog.template(id: victim.id) == nil)
        #expect(result.catalog.sharedComponents.allSatisfy { !$0.isMember(victim.id) })
        #expect(fixture.store.load().template(id: victim.id) == nil)
    }

    @Test("Wirings ride only with imported hook files")
    func wiringsFollowImportedHooks() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let component = SharedComponent(
            id: "my-comp", name: "My Comp",
            files: [ComponentFile(kind: .hook, name: "my-hook")],
            order: 50, memberTemplateIDs: [])
        try fixture.writeManifest(
            TemplateArchiveManifest(
                base: fixture.catalog.base,
                sharedComponents: [component],
                hookWirings: [
                    HookWiring(name: "my-hook", event: .stop),
                    HookWiring(name: "base-hook", event: .sessionStart),
                ]
            ))
        try fixture.writeStaged("hooks/my-hook.sh")
        try fixture.writeStaged("hooks/base-hook.sh")

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["component:my-comp"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )

        #expect(result.hookWirings.wiring(named: "my-hook") != nil)
        #expect(result.hookWirings.wiring(named: "base-hook") == nil)
        let persisted = try HookWiringStore.load(from: fixture.wiringsURL)
        #expect(persisted == result.hookWirings)
    }

    @Test("A failing manifest save rolls copied files back")
    func manifestSaveFailureRollsBack() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        try fixture.writeLocal("templates/my-temp/CLAUDE.md", "precious local")
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md", "archive bytes")
        try fixture.writeStaged("templates/my-temp/hooks/new-hook.sh", "new")

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let failingStore = TemplateCatalogStore(manifestURL: nil)
        #expect(throws: (any Error).self) {
            try importer.apply(
                contents,
                selectedItemIDs: ["template:my-temp"],
                store: failingStore,
                hookWirings: HookWiringStore(),
                hookWiringsURL: fixture.wiringsURL
            )
        }

        #expect(fixture.localData("templates/my-temp/CLAUDE.md") == Data("precious local".utf8))
        #expect(fixture.localData("templates/my-temp/hooks/new-hook.sh") == nil)
    }

    @Test("A kind mismatch replaces the other-kind item entirely")
    func kindMismatchReplaces() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        fixture.catalog.sharedComponents.append(
            SharedComponent(id: "clash", name: "Clash", files: [], order: 9, memberTemplateIDs: []))
        let template = customTemplate(id: "clash", categoryID: categoryID)
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["template:clash"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )

        #expect(result.catalog.template(id: "clash") == template)
        #expect(result.catalog.sharedComponent(id: "clash") == nil)
    }

    @Test("A missing category travels with the template; a local one is never overwritten")
    func categoryEnsuredNotOverwritten() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let newCategory = TemplateCategory(id: "fresh-cat", name: "Fresh", order: 42)
        let template = customTemplate(id: "my-temp", categoryID: "fresh-cat")
        try fixture.writeManifest(
            TemplateArchiveManifest(categories: [newCategory], templates: [template]))

        let importer = fixture.importer()
        let contents = try importer.contents(stagingDir: fixture.staging)
        let result = try importer.apply(
            contents,
            selectedItemIDs: ["template:my-temp"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )
        #expect(result.catalog.category(id: "fresh-cat") == newCategory)

        // Second run with a locally renamed category: the rename survives.
        fixture.catalog = result.catalog
        let index = try #require(
            fixture.catalog.categories.firstIndex(where: { $0.id == "fresh-cat" }))
        fixture.catalog.categories[index] = TemplateCategory(
            id: "fresh-cat", name: "Renamed Locally", order: 42)
        let second = try fixture.importer().apply(
            try fixture.importer().contents(stagingDir: fixture.staging),
            selectedItemIDs: ["template:my-temp"],
            store: fixture.store,
            hookWirings: HookWiringStore(),
            hookWiringsURL: fixture.wiringsURL
        )
        #expect(second.catalog.category(id: "fresh-cat")?.name == "Renamed Locally")
    }
}

@Suite("TemplateArchive roundtrip (integration)", .tags(.integration))
struct TemplateArchiveRoundtripIntegrationTests {
    private func makeStore(_ name: String) throws -> (root: URL, overrides: ScaffoldOverrides) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-roundtrip-\(name)-\(UUID().uuidString)")
        let bundled = root.appending(path: "bundled")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        return (
            root,
            ScaffoldOverrides(bundledRoot: bundled, overrideRoot: root.appending(path: "override"))
        )
    }

    @Test("Full export → import into a fresh store reproduces records, files, and wirings")
    func fullRoundtripIsByteIdentical() async throws {
        let source = try makeStore("src")
        let target = try makeStore("dst")
        defer {
            try? FileManager.default.removeItem(at: source.root)
            try? FileManager.default.removeItem(at: target.root)
        }

        var catalog = TemplateCatalog.bundledDefault
        let categoryID = catalog.sortedCategories[0].id
        let deleted = try #require(catalog.templates.first(where: { $0.predefined }))
        catalog.deleteTemplate(id: deleted.id)
        catalog.templates.append(
            TemplateDescriptor(
                id: "my-temp", name: "My Temp", image: .symbol("star"), categoryID: categoryID,
                predefined: false, order: 99, templateLayers: ["my-temp"], gitignoreTags: [],
                mcpServers: [], gateCommands: .xcode, stackSummary: "", xcodeMcpLine: ""))
        try source.overrides.writeOverride("layer", toRelative: "templates/my-temp/CLAUDE.md")
        try source.overrides.writeOverride("hook", toRelative: "hooks/user-hook.sh")
        try source.overrides.writeOverride("doc", toRelative: "docs/notes.md")
        let wiring = HookWiring(name: "user-hook", event: .sessionStart)

        let archive = source.root.appending(path: "backup.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: catalog, overrides: source.overrides,
            hookWirings: HookWiringStore(wirings: [wiring])
        ).export(.fullCatalog, to: archive)

        let importer = TemplateArchiveImporter(
            catalog: .bundledDefault, overrides: target.overrides)
        let contents = try await importer.read(archiveURL: archive)
        defer { contents.cleanup() }

        // Restoring a backup on a fresh store runs without a single warning.
        #expect(contents.items.allSatisfy { !$0.conflict })

        let result = try importer.apply(
            contents,
            selectedItemIDs: Set(contents.items.map(\.id)),
            store: TemplateCatalogStore(manifestURL: target.root.appending(path: "manifest.json")),
            hookWirings: HookWiringStore(),
            hookWiringsURL: target.root.appending(path: "hook-wirings.json")
        )

        #expect(result.catalog == catalog)
        #expect(result.hookWirings.wirings == [wiring])
        for relative in ["templates/my-temp/CLAUDE.md", "hooks/user-hook.sh", "docs/notes.md"] {
            let sourceData = try Data(
                contentsOf: try #require(source.overrides.overrideURL(forRelative: relative)))
            let targetData = try Data(
                contentsOf: try #require(target.overrides.overrideURL(forRelative: relative)))
            #expect(sourceData == targetData, "\(relative) differs")
        }
        #expect(
            target.overrides.overrideFileNamesRecursive(inRelativeDir: "")
                == source.overrides.overrideFileNamesRecursive(inRelativeDir: ""))
    }

    @Test("A single-template export imported into an empty store yields a working template")
    func singleTemplateSelfContained() async throws {
        let source = try makeStore("src")
        let target = try makeStore("dst")
        defer {
            try? FileManager.default.removeItem(at: source.root)
            try? FileManager.default.removeItem(at: target.root)
        }

        var catalog = TemplateCatalog.bundledDefault
        let categoryID = catalog.sortedCategories[0].id
        catalog.templates.append(
            TemplateDescriptor(
                id: "my-temp", name: "My Temp", image: .symbol("star"), categoryID: categoryID,
                predefined: false, order: 99, templateLayers: ["my-temp"], gitignoreTags: [],
                mcpServers: [], gateCommands: .xcode, stackSummary: "", xcodeMcpLine: ""))
        catalog.sharedComponents.append(
            SharedComponent(
                id: "my-comp", name: "My Comp",
                files: [ComponentFile(kind: .layer, name: "my-comp-layer")],
                order: 50, memberTemplateIDs: ["my-temp"]))
        try source.overrides.writeOverride("layer", toRelative: "templates/my-temp/CLAUDE.md")
        try source.overrides.writeOverride(
            "comp layer", toRelative: "templates/my-comp-layer/CLAUDE.md")

        let archive = source.root.appending(path: "single.plumagetemplates")
        try await TemplateArchiveExporter(
            catalog: catalog, overrides: source.overrides, hookWirings: HookWiringStore()
        ).export(.template("my-temp"), to: archive)

        let importer = TemplateArchiveImporter(
            catalog: .bundledDefault, overrides: target.overrides)
        let contents = try await importer.read(archiveURL: archive)
        defer { contents.cleanup() }
        let result = try importer.apply(
            contents,
            selectedItemIDs: Set(contents.items.map(\.id)),
            store: TemplateCatalogStore(manifestURL: target.root.appending(path: "manifest.json")),
            hookWirings: HookWiringStore(),
            hookWiringsURL: nil
        )

        let imported = try #require(result.catalog.template(id: "my-temp"))
        #expect(imported.name == "My Temp")
        #expect(result.catalog.sharedComponents(forTemplate: "my-temp").map(\.id) == ["my-comp"])
        #expect(result.catalog.category(id: categoryID) != nil)
        #expect(
            target.overrides.hasOverride(forRelative: "templates/my-temp/CLAUDE.md"))
        #expect(
            target.overrides.hasOverride(forRelative: "templates/my-comp-layer/CLAUDE.md"))
    }
}
