import Foundation
import Testing

@testable import Plumage

// Finder import must be repeatable in one session: every dropped file lands in the override
// store and shows in the tree. The drag-once defect was in the view layer (the outline lost
// cross-process drops after a relayout), not here — this pins the model contract it relies on.
@MainActor
@Suite("TemplateManager Finder-import re-entry")
struct TemplateManagerImportReentryTests {
    private func makeModel() -> (model: TemplateManagerModel, override: URL, source: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        let source = base.appending(path: "source", directoryHint: .isDirectory)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        try? fm.createDirectory(at: source, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, override, source, { try? fm.removeItem(at: base) })
    }

    private func writeFile(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    @Test("a second Finder import in the same session imports again at Base")
    func repeatedImportsSucceedAtBase() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let first = try writeFile("first.md", in: ctx.source)
        #expect(ctx.model.importDropped(urls: [first], intoStoreDir: ctx.model.activeScope.storageRoot))
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: "first.md").path))

        // The exact symptom of the fixed bug: the second drop did nothing. It must import now.
        let second = try writeFile("second.md", in: ctx.source)
        #expect(ctx.model.importDropped(urls: [second], intoStoreDir: ctx.model.activeScope.storageRoot))
        #expect(FileManager.default.fileExists(atPath: ctx.override.appending(path: "second.md").path))

        let names = Set(TemplateManagerModel.flattenLeaves(ctx.model.contentTree).map(\.name))
        #expect(names.contains("first.md"))
        #expect(names.contains("second.md"))
    }

    @Test("repeated imports work under a template scope too")
    func repeatedImportsInTemplateScope() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()

        let first = try writeFile("a.md", in: ctx.source)
        #expect(ctx.model.importDropped(urls: [first], intoStoreDir: ctx.model.activeScope.storageRoot))
        let second = try writeFile("b.md", in: ctx.source)
        #expect(ctx.model.importDropped(urls: [second], intoStoreDir: ctx.model.activeScope.storageRoot))

        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/macOS/a.md").path))
        #expect(
            FileManager.default.fileExists(
                atPath: ctx.override.appending(path: "templates/macOS/b.md").path))
    }
}
