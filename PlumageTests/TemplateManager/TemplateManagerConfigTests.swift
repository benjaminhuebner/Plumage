import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManager generated configs")
struct TemplateManagerConfigTests {
    private func makeModel() -> (model: TemplateManagerModel, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMConfig-\(UUID().uuidString)", directoryHint: .isDirectory)
        let override = base.appending(path: "override", directoryHint: .isDirectory)
        try? fm.createDirectory(at: override, withIntermediateDirectories: true)
        let model = TemplateManagerModel(
            store: TemplateCatalogStore(manifestURL: nil),
            overrides: ScaffoldOverrides(bundledRoot: RepoAssets.root, overrideRoot: override),
            hookWiringStoreURL: base.appending(path: "hooks.json"))
        return (model, override, { try? fm.removeItem(at: base) })
    }

    private func find(_ nodes: [FileNode], path: [String]) -> FileNode? {
        guard let head = path.first else { return nil }
        guard let node = nodes.first(where: { $0.name == head }) else { return nil }
        if path.count == 1 { return node }
        return find(node.children ?? [], path: Array(path.dropFirst()))
    }

    @Test("Config nodes appear at their output positions even without an override")
    func configNodesPresent() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        #expect(find(ctx.model.contentTree, path: [".gitignore"]) != nil)
        #expect(find(ctx.model.contentTree, path: [".mcp.json"]) != nil)
        #expect(find(ctx.model.contentTree, path: [".claude", "settings.json"]) != nil)
    }

    @Test("Generated content is produced from the composers")
    func generatedContent() {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        // The macOS block is always appended to .gitignore.
        #expect(ctx.model.generatedConfigContent(.gitignore).contains(".DS_Store"))
        #expect(ctx.model.generatedConfigContent(.settings).contains("permissions"))
        #expect(ctx.model.generatedConfigContent(.mcp).contains("mcpServers"))
    }

    @Test("Editing a config seeds the override slot from the generated baseline")
    func configEditingSeedsFromGenerated() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        let node = ctx.model.configNode(.gitignore)

        ctx.model.beginEditing(node)

        #expect(ctx.model.editingFileURL == ctx.override.appending(path: ".gitignore"))
        let fallback = try #require(ctx.model.editingFallbackURL)
        let seeded = try String(contentsOf: fallback, encoding: .utf8)
        #expect(seeded.contains(".DS_Store"))
        // A config resets (regenerates), it is not user-authored / deletable.
        #expect(!ctx.model.isUserAuthored(node))
    }

    @Test("A template tier shows a read-only settings preview with only its own wirings")
    func templateTierSettingsPreview() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .template("macOS")
        ctx.model.refreshContent()
        let hook = try #require(ctx.model.addUserFile(kind: .hook, rawName: "tmpl-hook"))
        ctx.model.saveWiring(forHook: hook, event: .stop, matcher: nil)
        ctx.model.refreshContent()

        let node = try #require(find(ctx.model.contentTree, path: [".claude", "settings.json"]))
        ctx.model.beginEditing(node)

        #expect(ctx.model.editingFileURL == nil)
        let preview = try #require(ctx.model.editingPreviewText)
        #expect(preview.contains("tmpl-hook.sh"))
        // Inherited Base wirings are not the template's contribution.
        #expect(!preview.contains("force-plumage-skill"))
        #expect(!ctx.model.isUserAuthored(node))
    }

    @Test("A component tier preview lists its built-in wirings, nothing inherited")
    func componentTierSettingsPreview() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()

        let node = try #require(find(ctx.model.contentTree, path: [".claude", "settings.json"]))
        ctx.model.beginEditing(node)

        let preview = try #require(ctx.model.editingPreviewText)
        #expect(preview.contains("format-swift.sh"))
        #expect(preview.contains("lint-swift.sh"))
        #expect(!preview.contains("force-plumage-skill"))
    }

    @Test("The Base settings preview omits foreign tier user hooks")
    func baseSettingsPreviewOmitsForeignHooks() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .sharedComponent("swift-shared")
        ctx.model.refreshContent()
        let hook = try #require(ctx.model.addUserFile(kind: .hook, rawName: "comp-hook"))
        ctx.model.saveWiring(forHook: hook, event: .stop, matcher: nil)

        #expect(!ctx.model.generatedConfigContent(.settings).contains("comp-hook"))
        // The component's own preview carries it instead.
        #expect(
            ctx.model.tierSettingsPreviewContent(for: .component("swift-shared"))
                .contains("comp-hook.sh"))
    }

    @Test("A saved config override marks the node overridden")
    func overriddenConfigMarks() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        try ctx.model.overrides.writeOverride("custom-ignore\n", toRelative: ".gitignore")
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let node = try #require(find(ctx.model.contentTree, path: [".gitignore"]))
        #expect(ctx.model.isOverridden(node))
    }
}
