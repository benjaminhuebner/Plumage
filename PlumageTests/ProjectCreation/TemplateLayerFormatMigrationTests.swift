import Foundation
import Testing

@testable import Plumage

@Suite("TemplateLayerFormatMigration")
struct TemplateLayerFormatMigrationTests {
    private func makeStore() -> (root: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "LayerFormat-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (root, { try? FileManager.default.removeItem(at: root) })
    }

    private func write(_ contents: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ root: URL, _ rel: String) -> String? {
        try? String(contentsOf: root.appending(path: rel), encoding: .utf8)
    }

    // MARK: - Pure transform

    @Test("Legacy open-only blocks gain closes and the spaced keyword is renamed")
    func closesAndRenames() {
        let legacy = "%% CONVENTIONS %%\n- a\n%% BUILD AND TEST %%\n- b"
        let rewritten = TemplateLayerFormatMigration.closeOpenBlocks(in: legacy)
        #expect(
            rewritten == "%% CONVENTIONS %%\n- a\n%% /CONVENTIONS %%\n%% BUILD_AND_TEST %%\n- b\n%% /BUILD_AND_TEST %%")
    }

    @Test("Content already in the new format transforms to itself (idempotent)")
    func idempotentOnNewFormat() {
        let modern = "%% CONVENTIONS %%\n- a\n%% /CONVENTIONS %%\n\n%% PITFALLS %%\n- b\n%% /PITFALLS %%"
        #expect(TemplateLayerFormatMigration.closeOpenBlocks(in: modern) == modern)
    }

    @Test("A file with no markers is unchanged")
    func noMarkersUnchanged() {
        let plain = "# Title\n\njust prose\n"
        #expect(TemplateLayerFormatMigration.closeOpenBlocks(in: plain) == plain)
    }

    // MARK: - Store migration

    @Test("A legacy layer override is rewritten in place; a modern one is left untouched")
    func migratesLegacyLayer() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("%% BUILD AND TEST %%\n- run it", to: ctx.root, rel: "templates/macos/CLAUDE.md")
        try write(
            "%% CONVENTIONS %%\n- x\n%% /CONVENTIONS %%", to: ctx.root, rel: "templates/ios/CLAUDE.md")
        try write("# <<<PROJECT_NAME>>>\n<<<CONVENTIONS>>>\n", to: ctx.root, rel: "templates/CLAUDE.md")

        let migrated = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated == ["macos"])
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "%% BUILD_AND_TEST %%\n- run it\n%% /BUILD_AND_TEST %%")
        #expect(read(ctx.root, "templates/ios/CLAUDE.md") == "%% CONVENTIONS %%\n- x\n%% /CONVENTIONS %%")
        #expect(read(ctx.root, "templates/CLAUDE.md") == "# <<<PROJECT_NAME>>>\n<<<CONVENTIONS>>>\n")
    }

    @Test("After migration the renamed block fills the placeholder it used to miss")
    func migratedBlockFillsPlaceholder() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("%% BUILD AND TEST %%\n- run it", to: ctx.root, rel: "templates/macos/CLAUDE.md")
        _ = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        let layer = try #require(read(ctx.root, "templates/macos/CLAUDE.md"))
        let merged = try PlaceholderMerge.merge(
            skeleton: "## Build and test\n<<<BUILD_AND_TEST>>>\n", contributions: [layer])
        #expect(merged == "## Build and test\n- run it\n")
    }

    @Test("No store at the override root is a no-op")
    func emptyStoreNoOp() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        #expect(TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root).isEmpty)
    }
}
