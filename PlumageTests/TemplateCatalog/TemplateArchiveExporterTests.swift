import Foundation
import Testing

@testable import Plumage

@Suite("TemplateArchiveExporter")
struct TemplateArchiveExporterTests {
    // MARK: - Synthetic store

    private struct Fixture {
        let root: URL
        let overrides: ScaffoldOverrides
        var catalog: TemplateCatalog

        func write(_ relative: String, _ content: String = "x") throws {
            try overrides.writeOverride(Data(content.utf8), toRelative: relative)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-export-\(UUID().uuidString)")
        let bundled = root.appending(path: "bundled")
        let override = root.appending(path: "override")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            overrides: ScaffoldOverrides(bundledRoot: bundled, overrideRoot: override),
            catalog: .bundledDefault
        )
    }

    private func customTemplate(id: String, categoryID: String) -> TemplateDescriptor {
        TemplateDescriptor(
            id: id,
            name: id,
            image: .symbol("star"),
            categoryID: categoryID,
            predefined: false,
            order: 99,
            templateLayers: [id],
            gitignoreTags: ["swift"],
            mcpServers: [],
            gateCommands: .xcode,
            stackSummary: "custom",
            xcodeMcpLine: ""
        )
    }

    private func exporter(_ fixture: Fixture, wirings: [HookWiring] = []) -> TemplateArchiveExporter {
        TemplateArchiveExporter(
            catalog: fixture.catalog,
            overrides: fixture.overrides,
            hookWirings: HookWiringStore(wirings: wirings)
        )
    }

    // MARK: - Single template

    @Test("A single-template export stages own files, member components, and image")
    func singleTemplateIsSelfContained() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        var template = customTemplate(id: "my-temp", categoryID: categoryID)
        template.image = .file("template-images/my-temp.png")
        fixture.catalog.templates.append(template)
        let component = SharedComponent(
            id: "my-comp",
            name: "My Comp",
            files: [
                ComponentFile(kind: .layer, name: "my-comp-layer"),
                ComponentFile(kind: .hook, name: "my-hook"),
            ],
            order: 50,
            memberTemplateIDs: ["my-temp"]
        )
        fixture.catalog.sharedComponents.append(component)

        try fixture.write("templates/my-temp/CLAUDE.md")
        try fixture.write("templates/my-temp/hooks/temp-hook.py")
        try fixture.write("templates/my-comp-layer/CLAUDE.md")
        try fixture.write("hooks/my-hook.sh")
        try fixture.write("components/my-comp/docs/readme.md")
        try fixture.write("template-images/my-temp.png")
        try fixture.write("templates/unrelated/CLAUDE.md")

        let wiring = HookWiring(name: "my-hook", event: .stop)
        let unrelated = HookWiring(name: "other", event: .stop)
        let sut = exporter(fixture, wirings: [wiring, unrelated])

        let staged = try sut.stagedRelativePaths(for: .template("my-temp"))
        #expect(
            staged == [
                "components/my-comp/docs/readme.md",
                "hooks/my-hook.sh",
                "template-images/my-temp.png",
                "templates/my-comp-layer/CLAUDE.md",
                "templates/my-temp/CLAUDE.md",
                "templates/my-temp/hooks/temp-hook.py",
            ])

        let manifest = try sut.archiveManifest(for: .template("my-temp"))
        #expect(manifest.templates == [template])
        #expect(manifest.sharedComponents == [component])
        #expect(manifest.categories.map(\.id) == [categoryID])
        #expect(manifest.base == nil)
        #expect(manifest.hookWirings == [wiring])
    }

    @Test("A pristine predefined template exports manifest records only")
    func pristinePredefinedExportsRecordsOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let predefined = try #require(fixture.catalog.templates.first(where: { $0.predefined }))
        let sut = exporter(fixture)

        let staged = try sut.stagedRelativePaths(for: .template(predefined.id))
        #expect(staged.isEmpty)

        let manifest = try sut.archiveManifest(for: .template(predefined.id))
        #expect(manifest.templates == [predefined])
        #expect(
            manifest.sharedComponents
                == fixture.catalog.sharedComponents(forTemplate: predefined.id))
    }

    @Test("An unknown template id throws unknownItem")
    func unknownTemplateThrows() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        #expect(throws: TemplateArchiveExportError.unknownItem("ghost")) {
            try exporter(fixture).stagedRelativePaths(for: .template("ghost"))
        }
    }

    @Test("A referenced image missing from the store throws missingImageFile")
    func missingImageThrows() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let categoryID = fixture.catalog.sortedCategories[0].id
        var template = customTemplate(id: "my-temp", categoryID: categoryID)
        template.image = .file("template-images/my-temp.png")
        fixture.catalog.templates.append(template)

        #expect(
            throws: TemplateArchiveExportError.missingImageFile("template-images/my-temp.png")
        ) {
            try exporter(fixture).stagedRelativePaths(for: .template("my-temp"))
        }
    }

    // MARK: - Single component

    @Test("A component export stages typed files and its own subtree")
    func componentExportStagesTypedAndLooseFiles() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let component = SharedComponent(
            id: "my-comp",
            name: "My Comp",
            files: [
                ComponentFile(kind: .layer, name: "my-comp-layer"),
                ComponentFile(kind: .hook, name: "my-hook"),
                ComponentFile(kind: .config, name: "swift-format"),
            ],
            order: 50,
            memberTemplateIDs: []
        )
        fixture.catalog.sharedComponents.append(component)
        try fixture.write("templates/my-comp-layer/CLAUDE.md")
        try fixture.write("hooks/my-hook.py")
        try fixture.write("configs/swift-format")
        try fixture.write("components/my-comp/skills/helper/SKILL.md")
        try fixture.write("components/other/docs/x.md")

        let staged = try exporter(fixture).stagedRelativePaths(for: .sharedComponent("my-comp"))
        #expect(
            staged == [
                "components/my-comp/skills/helper/SKILL.md",
                "configs/swift-format",
                "hooks/my-hook.py",
                "templates/my-comp-layer/CLAUDE.md",
            ])

        let manifest = try exporter(fixture).archiveManifest(for: .sharedComponent("my-comp"))
        #expect(manifest.sharedComponents == [component])
        #expect(manifest.templates.isEmpty)
    }

    // MARK: - Base

    @Test("A base export stages everything outside template/component namespaces")
    func baseExportStaysInBaseNamespaces() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try fixture.write("templates/CLAUDE.md", "base claude override")
        try fixture.write("hooks/block-dangerous-bash.sh")
        try fixture.write("docs/notes.md")
        try fixture.write(".claude/loose.md")
        try fixture.write("templates/macos/CLAUDE.md")
        try fixture.write("components/swift-shared/docs/x.md")
        try fixture.write("template-images/foo.png")
        try fixture.overrides.suppress(relativePath: "docs/gone.md")

        let staged = try exporter(fixture).stagedRelativePaths(for: .base)
        #expect(
            staged == [
                ".claude/loose.md",
                "docs/notes.md",
                "hooks/block-dangerous-bash.sh",
                "templates/CLAUDE.md",
            ])

        let manifest = try exporter(fixture).archiveManifest(for: .base)
        #expect(manifest.base == fixture.catalog.base)
        #expect(manifest.templates.isEmpty)
    }

    // MARK: - Full catalog

    @Test("A full export stages every override file and carries tombstone records")
    func fullCatalogIncludesEverythingAndTombstones() throws {
        var fixture = try makeFixture()
        defer { fixture.cleanup() }
        let deleted = try #require(fixture.catalog.templates.first(where: { $0.predefined }))
        fixture.catalog.templates.removeAll { $0.id == deleted.id }
        try fixture.write("templates/macos/CLAUDE.md")
        try fixture.write("components/swift-shared/docs/x.md")
        try fixture.write("hooks/user-hook.sh")
        try fixture.overrides.suppress(relativePath: "docs/gone.md")

        let wiring = HookWiring(name: "user-hook", event: .sessionStart)
        let sut = exporter(fixture, wirings: [wiring])

        let staged = try sut.stagedRelativePaths(for: .fullCatalog)
        #expect(
            staged == [
                "components/swift-shared/docs/x.md",
                "hooks/user-hook.sh",
                "templates/macos/CLAUDE.md",
            ])

        let manifest = try sut.archiveManifest(for: .fullCatalog)
        #expect(manifest.tombstones.contains(Tombstone(kind: .template, id: deleted.id)))
        #expect(manifest.templates == fixture.catalog.templates)
        #expect(manifest.base == fixture.catalog.base)
        #expect(manifest.hookWirings == [wiring])
    }
}

@Suite("TemplateArchiveExporter (integration)", .tags(.integration))
struct TemplateArchiveExporterIntegrationTests {
    @Test("Exporting packs manifest and staged files into a readable archive")
    func exportProducesReadableArchive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "archive-export-int-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appending(path: "bundled")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let overrides = ScaffoldOverrides(
            bundledRoot: bundled, overrideRoot: root.appending(path: "override"))
        var catalog = TemplateCatalog.bundledDefault
        let categoryID = catalog.sortedCategories[0].id
        catalog.templates.append(
            TemplateDescriptor(
                id: "my-temp", name: "My Temp", image: .symbol("star"),
                categoryID: categoryID, predefined: false, order: 99,
                templateLayers: ["my-temp"], gitignoreTags: [], mcpServers: [],
                gateCommands: .xcode, stackSummary: "", xcodeMcpLine: ""))
        try overrides.writeOverride("layer-bytes", toRelative: "templates/my-temp/CLAUDE.md")

        let exporter = TemplateArchiveExporter(
            catalog: catalog, overrides: overrides, hookWirings: HookWiringStore())
        let archive = root.appending(path: "out.plumagetemplates")
        try await exporter.export(.template("my-temp"), to: archive)

        let unpacked = root.appending(path: "unpacked")
        try await TemplateArchiveZip().unpack(archive: archive, to: unpacked)
        let manifestData = try Data(
            contentsOf: unpacked.appending(path: TemplateArchiveExporter.manifestFileName))
        let manifest = try JSONDecoder().decode(TemplateArchiveManifest.self, from: manifestData)
        #expect(manifest.templates.map(\.id) == ["my-temp"])
        let layer = try String(
            contentsOf: unpacked.appending(path: "templates/my-temp/CLAUDE.md"), encoding: .utf8)
        #expect(layer == "layer-bytes")
    }
}
