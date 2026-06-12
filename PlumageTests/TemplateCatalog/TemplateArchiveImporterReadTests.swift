import Foundation
import Testing

@testable import Plumage

@Suite("TemplateArchiveImporter read side")
struct TemplateArchiveImporterReadTests {
    private struct Fixture {
        let root: URL
        let overrides: ScaffoldOverrides
        let staging: URL
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

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-import-\(UUID().uuidString)")
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
            catalog: .bundledDefault
        )
    }

    private func customTemplate(
        id: String, categoryID: String, image: TemplateImage = .symbol("star")
    ) -> TemplateDescriptor {
        TemplateDescriptor(
            id: id, name: id, image: image, categoryID: categoryID, predefined: false,
            order: 99, templateLayers: [id], gitignoreTags: [], mcpServers: [],
            gateCommands: .xcode, stackSummary: "", xcodeMcpLine: "")
    }

    // MARK: - Validation

    @Test("An unknown tombstone kind reports a newer-Plumage message, not invalid manifest")
    func unknownTombstoneKindRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.writeStaged(
            TemplateArchiveExporter.manifestFileName,
            #"{"schemaVersion": 1, "tombstones": [{"kind": "wormhole", "id": "x"}]}"#)

        let expected = TemplateArchiveImportError.unknownKind(
            field: "deleted-item kind", value: "wormhole")
        #expect(expected.localizedDescription.contains("newer Plumage"))
        #expect(throws: expected) {
            _ = try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    @Test("An unknown component file kind reports a newer-Plumage message")
    func unknownComponentKindRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let manifest = """
            {"schemaVersion": 1, "sharedComponents": [{"id": "c", "name": "C", "order": 0,
             "memberTemplateIDs": [], "files": [{"kind": "blob", "name": "n"}]}]}
            """
        try fixture.writeStaged(TemplateArchiveExporter.manifestFileName, manifest)

        #expect(
            throws: TemplateArchiveImportError.unknownKind(field: "component file kind", value: "blob")
        ) {
            _ = try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    @Test("A missing archive manifest is rejected")
    func missingManifestRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        #expect(throws: TemplateArchiveImportError.self) {
            try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    @Test("Garbage manifest JSON is rejected as invalidManifest")
    func garbageManifestRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.writeStaged(TemplateArchiveExporter.manifestFileName, "{not json")
        do {
            _ = try fixture.importer().contents(stagingDir: fixture.staging)
            Issue.record("expected invalidManifest")
        } catch let error as TemplateArchiveImportError {
            guard case .invalidManifest = error else {
                Issue.record("expected invalidManifest, got \(error)")
                return
            }
        }
    }

    @Test("A newer schemaVersion maps to the newerSchema import error")
    func newerSchemaRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.writeStaged(TemplateArchiveExporter.manifestFileName, #"{"schemaVersion": 7}"#)
        #expect(throws: TemplateArchiveImportError.newerSchema(found: 7, supported: 1)) {
            try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    @Test("A referenced image missing from the archive is rejected")
    func missingImageRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(
            id: "my-temp", categoryID: categoryID, image: .file("template-images/my-temp.png"))
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))

        #expect(
            throws: TemplateArchiveImportError.missingImageFile("template-images/my-temp.png")
        ) {
            try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    @Test("An image no manifest record references is rejected")
    func unreferencedImageRejected() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.writeManifest(TemplateArchiveManifest())
        try fixture.writeStaged("template-images/orphan.png")

        #expect(
            throws: TemplateArchiveImportError.unreferencedImage("template-images/orphan.png")
        ) {
            try fixture.importer().contents(stagingDir: fixture.staging)
        }
    }

    // MARK: - Items and attribution

    @Test("Items carry attributed files; base gets the unclaimed remainder")
    func itemsAttributeFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        let component = SharedComponent(
            id: "my-comp", name: "My Comp",
            files: [ComponentFile(kind: .hook, name: "my-hook")],
            order: 50, memberTemplateIDs: ["my-temp"])
        try fixture.writeManifest(
            TemplateArchiveManifest(
                base: fixture.catalog.base,
                categories: [TemplateCategory(id: categoryID, name: "Cat", order: 0)],
                sharedComponents: [component],
                templates: [template],
                tombstones: [Tombstone(kind: .template, id: "gone")]
            ))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md")
        try fixture.writeStaged("hooks/my-hook.sh")
        try fixture.writeStaged("hooks/base-hook.sh")
        try fixture.writeStaged("docs/notes.md")

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(
            contents.items.map(\.id) == [
                "base", "component:my-comp", "template:my-temp", "deleted-defaults",
            ])
        let byID = Dictionary(uniqueKeysWithValues: contents.items.map { ($0.id, $0) })
        #expect(byID["component:my-comp"]?.files == ["hooks/my-hook.sh"])
        #expect(byID["template:my-temp"]?.files == ["templates/my-temp/CLAUDE.md"])
        #expect(byID["base"]?.files == ["docs/notes.md", "hooks/base-hook.sh"])
        #expect(byID["deleted-defaults"]?.kind == .deletedDefaults(count: 1))
    }

    // MARK: - Conflict semantics

    @Test("Byte-identical records and files are a no-op, not a conflict")
    func byteIdenticalIsNoConflict() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        fixture.catalog.templates.append(template)
        try fixture.writeLocal("templates/my-temp/CLAUDE.md", "same bytes")
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md", "same bytes")

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(contents.items.map(\.conflict) == [false])
    }

    @Test("Different archive bytes over a local override flag a conflict")
    func localOverrideConflicts() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        let template = customTemplate(id: "my-temp", categoryID: categoryID)
        fixture.catalog.templates.append(template)
        try fixture.writeLocal("templates/my-temp/CLAUDE.md", "local edit")
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))
        try fixture.writeStaged("templates/my-temp/CLAUDE.md", "archive bytes")

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(contents.items.map(\.conflict) == [true])
    }

    @Test("A changed record over a pristine predefined item overlays silently")
    func pristinePredefinedOverlaysSilently() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var renamed = try #require(fixture.catalog.templates.first(where: { $0.predefined }))
        renamed.name = "Renamed In Archive"
        try fixture.writeManifest(TemplateArchiveManifest(templates: [renamed]))

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(contents.items.map(\.conflict) == [false])
    }

    @Test("A changed record over a locally modified item flags a conflict")
    func modifiedRecordConflicts() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let index = try #require(
            fixture.catalog.templates.firstIndex(where: { $0.predefined }))
        fixture.catalog.templates[index].name = "Locally Renamed"
        var archive = fixture.catalog.templates[index]
        archive.name = "Archive Rename"
        try fixture.writeManifest(TemplateArchiveManifest(templates: [archive]))

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(contents.items.map(\.conflict) == [true])
    }

    @Test("An archive template colliding with a local component is a kind-mismatch conflict")
    func kindMismatchConflicts() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        fixture.catalog.sharedComponents.append(
            SharedComponent(id: "clash", name: "Clash", files: [], order: 9, memberTemplateIDs: []))
        let template = customTemplate(id: "clash", categoryID: categoryID)
        try fixture.writeManifest(TemplateArchiveManifest(templates: [template]))

        let contents = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(contents.items.map(\.conflict) == [true])
    }

    @Test("A tombstone for a locally modified item flags the deletions row")
    func tombstoneOverModifiedItemConflicts() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let index = try #require(
            fixture.catalog.templates.firstIndex(where: { $0.predefined }))
        let id = fixture.catalog.templates[index].id
        try fixture.writeManifest(
            TemplateArchiveManifest(tombstones: [Tombstone(kind: .template, id: id)]))

        let pristine = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(pristine.items.map(\.conflict) == [false])

        fixture.catalog.templates[index].name = "Locally Renamed"
        let modified = try fixture.importer().contents(stagingDir: fixture.staging)
        #expect(modified.items.map(\.conflict) == [true])
    }
}

@Suite("TemplateArchiveImporter read (integration)", .tags(.integration))
struct TemplateArchiveImporterReadIntegrationTests {
    @Test("Garbage bytes fail read() with corruptArchive and leave no staging dir")
    func corruptArchiveRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-import-int-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let garbage = root.appending(path: "garbage.plumagetemplates")
        try Data("not a zip".utf8).write(to: garbage)

        let importer = TemplateArchiveImporter(
            catalog: .bundledDefault,
            overrides: ScaffoldOverrides(
                bundledRoot: root, overrideRoot: root.appending(path: "override")))
        await #expect(throws: TemplateArchiveZipError.self) {
            _ = try await importer.read(archiveURL: garbage)
        }
    }
}
