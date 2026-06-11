import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TemplateManager content selection rules")
struct TemplateContentSelectionRulesTests {
    private func makeModel() -> (model: TemplateManagerModel, override: URL, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(
            path: "TMSelectionRules-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test("Generated configs are read-only content nodes, user files are not")
    func readOnlyNodes() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let config = try #require(find(ctx.model.contentTree, path: [".gitignore"]))
        #expect(ctx.model.isReadOnlyContentNode(config))

        let created = try #require(ctx.model.addUserFile(kind: .doc, rawName: "guide"))
        #expect(!ctx.model.isReadOnlyContentNode(created))
    }

    @Test("Batch delete is offered only for all-user-authored selections")
    func batchDeleteEligibility() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let userFile = try #require(ctx.model.addUserFile(kind: .doc, rawName: "first"))
        let otherFile = try #require(ctx.model.addUserFile(kind: .doc, rawName: "second"))
        let bundled = try #require(find(ctx.model.contentTree, path: [".gitignore"]))

        #expect(ctx.model.canBatchDelete([userFile, otherFile]))
        #expect(!ctx.model.canBatchDelete([userFile, bundled]))
        #expect(!ctx.model.canBatchDelete([]))
    }

    @Test("Batch delete trashes every node after one confirmation")
    func batchDeleteTrashesAll() throws {
        let ctx = makeModel()
        defer { ctx.cleanup() }
        ctx.model.selection = .base
        ctx.model.refreshContent()

        let first = try #require(ctx.model.addUserFile(kind: .doc, rawName: "one"))
        let second = try #require(ctx.model.addUserFile(kind: .doc, rawName: "two"))

        ctx.model.requestDelete(batch: [first, second])
        #expect(ctx.model.pendingBatchDelete?.count == 2)

        ctx.model.confirmPendingBatchDelete()
        #expect(ctx.model.pendingBatchDelete == nil)
        let names = TemplateManagerModel.flattenLeaves(ctx.model.contentTree).map(\.name)
        #expect(!names.contains("one.md"))
        #expect(!names.contains("two.md"))
    }
}
