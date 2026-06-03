import Foundation
import Testing

@testable import Plumage

// Every selection renders the same `.claude/`-output structure: a component's hooks
// under `.claude/hooks`, layer fragments as `.claude/CLAUDE.md`, and add works in any
// selection (a matching-kind add joins the component).
@MainActor
@Suite("TemplateManager per-selection output tree")
struct TemplateManagerSelectionTreeTests {
    private func makeModel() -> (model: TemplateManagerModel, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMSel-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test("A hook component shows its hooks under .claude/hooks")
    func hookComponentStructure() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        #expect(find(ctx.model.contentTree, [".claude", "hooks", "format-swift.sh"]) != nil)
        #expect(find(ctx.model.contentTree, [".claude", "hooks", "lint-swift.sh"]) != nil)
    }

    @Test("A layer component shows its fragment as .claude/CLAUDE.md (not the layer name)")
    func layerComponentNamedClaudeMd() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(find(ctx.model.contentTree, [".claude", "CLAUDE.md"]))
        #expect(node.name == "CLAUDE.md")
        #expect(node.relativePath == "templates/swift-shared/CLAUDE.md")  // store path under the hood
    }

    @Test("A template shows the project structure with its own CLAUDE.md fragment")
    func templateStructure() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()

        let claudeMd = try #require(find(ctx.model.contentTree, [".claude", "CLAUDE.md"]))
        #expect(claudeMd.relativePath == "templates/macos/CLAUDE.md")  // the template's own layer
        // Same folder structure as Base: hooks live under .claude/hooks.
        #expect(find(ctx.model.contentTree, [".claude", "hooks"])?.isDirectory == true)
    }

    @Test("A bundled hook is not flagged as needing wiring (it is wired by the composer)")
    func bundledHookNotFlagged() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let hook = try #require(find(ctx.model.contentTree, [".claude", "hooks", "format-swift.sh"]))
        #expect(!ctx.model.needsWiring(hook))
        // The containing folder therefore shows no aggregate warning either.
        let hooksFolder = try #require(find(ctx.model.contentTree, [".claude", "hooks"]))
        #expect(!ctx.model.aggregateNeedsWiring(hooksFolder))
    }

    @Test("Adding a hook while a hook component is selected joins it and shows under .claude/hooks")
    func addHookJoinsComponent() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(ctx.model.addUserFile(kind: .hook, rawName: "my-extra-hook"))
        #expect(node.relativePath == "hooks/my-extra-hook.sh")
        // It is now part of the component's hook membership…
        #expect(
            ctx.model.catalog.sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-extra-hook") == true)
        // …and shows under .claude/hooks in the component tree.
        #expect(find(ctx.model.contentTree, [".claude", "hooks", "my-extra-hook.sh"]) != nil)
    }
}
