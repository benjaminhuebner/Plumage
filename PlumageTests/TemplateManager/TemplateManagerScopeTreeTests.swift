import Foundation
import Testing

@testable import Plumage

// The display-leak fix (#00078): loose files authored in one tier show only in that
// tier's tree, and Base never dumps a sibling tier's subtree.
@MainActor
@Suite("TemplateManager scope-owned content tree (#00078)")
struct TemplateManagerScopeTreeTests {
    private func makeModel() -> (model: TemplateManagerModel, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMScope-\(UUID().uuidString)", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json")),
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, { try? fm.removeItem(at: base) })
    }

    private func find(_ nodes: [FileNode], _ path: [String]) -> FileNode? {
        guard let head = path.first, let node = nodes.first(where: { $0.name == head }) else { return nil }
        return path.count == 1 ? node : find(node.children ?? [], Array(path.dropFirst()))
    }

    @Test("A doc authored in a template scope shows there, not in another template, not in Base")
    func templateDocIsScoped() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# A", toRelative: "templates/macOS/docs/a-only.md")

        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()
        let leaf = try #require(find(ctx.model.contentTree, [".claude", "docs", "a-only.md"]))
        #expect(leaf.relativePath == "templates/macOS/docs/a-only.md")  // scoped store path under the hood

        ctx.model.selection = .template("iOS")
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, [".claude", "docs", "a-only.md"]) == nil)

        ctx.model.selection = .base
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, [".claude", "docs", "a-only.md"]) == nil)
    }

    @Test("A Shared Component owns a loose folder; sibling tiers never show it")
    func componentFolderIsScoped() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride(
            "x", toRelative: "components/swift-shared/myfolder/note.txt")

        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, ["myfolder"])?.isDirectory == true)
        #expect(find(ctx.model.contentTree, ["myfolder", "note.txt"]) != nil)
        // The component still shows its composition slots, never the base project configs.
        #expect(find(ctx.model.contentTree, [".claude", "CLAUDE.md"]) != nil)
        #expect(find(ctx.model.contentTree, [".claude", "issues", "_TEMPLATE.md"]) == nil)

        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, ["myfolder"]) == nil)
        ctx.model.selection = .base
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, ["myfolder"]) == nil)
    }

    @Test("Base never dumps a template/component subtree as a folder (risk #2)")
    func baseDoesNotLeakSiblingSubtrees() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("# A", toRelative: "templates/macOS/docs/a.md")
        try ctx.model.overrides.writeOverride("x", toRelative: "components/swift-shared/c.txt")

        ctx.model.selection = .base
        ctx.model.refreshContent()
        #expect(find(ctx.model.contentTree, ["templates"]) == nil)
        #expect(find(ctx.model.contentTree, ["components"]) == nil)
        #expect(find(ctx.model.contentTree, [".claude", "docs", "a.md"]) == nil)
    }

    // MARK: - Path mapping (risk #1)

    @Test("Scope-aware path mapping round-trips per tier")
    func pathMappingRoundTrip() {
        for scope in [ManagerScope.base, .template("macOS"), .component("swift-shared")] {
            let docStore = TemplateManagerModel.storageDir(forOutputFolder: ".claude/docs", scope: scope)
            #expect(
                TemplateManagerModel.outputPath(forStorageDir: docStore, scope: scope) == ".claude/docs")
            let arbStore = TemplateManagerModel.storageDir(forOutputFolder: "myfolder", scope: scope)
            #expect(TemplateManagerModel.outputPath(forStorageDir: arbStore, scope: scope) == "myfolder")
        }
    }

    @Test("A tier's store dir is invisible to a different tier's mapping")
    func crossScopeMappingRejected() {
        let dir = "templates/macOS/docs"
        #expect(TemplateManagerModel.outputPath(forStorageDir: dir, scope: .template("macOS")) == ".claude/docs")
        #expect(TemplateManagerModel.outputPath(forStorageDir: dir, scope: .base) == nil)
        #expect(TemplateManagerModel.outputPath(forStorageDir: dir, scope: .template("iOS")) == nil)
        // The scope root itself maps to no project folder.
        #expect(
            TemplateManagerModel.outputPath(forStorageDir: "templates/macOS", scope: .template("macOS")) == nil)
    }
}
