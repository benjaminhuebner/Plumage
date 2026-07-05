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

    // MARK: - Pure transforms

    @Test("Legacy blocks become their section headings; the spaced keyword maps too")
    func blocksBecomeHeadings() {
        let legacy = "%% CONVENTIONS %%\n- a\n%% BUILD AND TEST %%\n- b"
        let rewritten = TemplateLayerFormatMigration.headingSections(from: legacy)
        #expect(rewritten == "## Conventions\n- a\n## Build and test\n- b")
    }

    @Test("Closed blocks convert too; the close marker leaves no trace")
    func closedBlocksConvert() {
        let legacy = "%% CONVENTIONS %%\n- x\n%% /CONVENTIONS %%\n\n%% PITFALLS %%\n- y\n%% /PITFALLS %%"
        let rewritten = TemplateLayerFormatMigration.headingSections(from: legacy)
        #expect(rewritten == "## Conventions\n- x\n\n## Common pitfalls\n- y")
    }

    @Test("An unknown keyword becomes a literal heading")
    func unknownKeywordLiteralHeading() {
        let rewritten = TemplateLayerFormatMigration.headingSections(
            from: "%% refdocs %%\n- see PROJECT.md\n%% /refdocs %%")
        #expect(rewritten == "## refdocs\n- see PROJECT.md")
    }

    @Test("Excluded keywords drop their whole block")
    func excludedKeywordDropsBlock() {
        let legacy = "%% CONVENTIONS %%\n- keep\n%% /CONVENTIONS %%\n%% refdocs %%\n- consumed\n%% /refdocs %%"
        let rewritten = TemplateLayerFormatMigration.headingSections(
            from: legacy, excluding: ["refdocs"])
        #expect(rewritten == "## Conventions\n- keep")
    }

    @Test("Heading-format content transforms to itself (idempotent)")
    func idempotentOnHeadingFormat() {
        let modern = "## Conventions\n- a\n\n## Common pitfalls\n- b\n"
        #expect(TemplateLayerFormatMigration.headingSections(from: modern) == modern)
    }

    @Test("Skeleton stripping drops section placeholders but keeps scalars and headings")
    func skeletonStripping() {
        let legacy = "# <<<PROJECT_NAME>>>\n<<<PROJECT_TAGLINE>>>\n\n## Conventions\n<<<CONVENTIONS>>>\n"
        let stripped = TemplateLayerFormatMigration.strippingSectionPlaceholders(from: legacy)
        #expect(stripped == "# <<<PROJECT_NAME>>>\n<<<PROJECT_TAGLINE>>>\n\n## Conventions\n")
    }

    @Test("A skeleton maps custom keywords to the heading directly above them")
    func skeletonKeywordHeadingMap() {
        let skeleton = "# <<<PROJECT_NAME>>>\n\n## Reference docs\n<<<refdocs>>>\n\n## Stack\n<<<STACK_SUMMARY>>>\n"
        let map = TemplateLayerFormatMigration.headingsByKeyword(inSkeleton: skeleton)
        #expect(map == ["refdocs": "## Reference docs"])
    }

    // MARK: - Store migration

    @Test("Legacy layer overrides rewrite to headings; heading-format files stay untouched")
    func migratesLegacyLayer() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("%% BUILD AND TEST %%\n- run it", to: ctx.root, rel: "templates/macos/CLAUDE.md")
        try write("## Conventions\n- x\n", to: ctx.root, rel: "templates/ios/CLAUDE.md")

        let migrated = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated == ["macos"])
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "## Build and test\n- run it")
        #expect(read(ctx.root, "templates/ios/CLAUDE.md") == "## Conventions\n- x\n")
    }

    @Test("A skeleton override loses its section placeholders; custom blocks follow its headings")
    func migratesSkeletonAndCustomKeyword() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write(
            "# <<<PROJECT_NAME>>>\n\n## Reference docs\n<<<refdocs>>>\n",
            to: ctx.root, rel: "templates/CLAUDE.md")
        try write(
            "%% refdocs %%\n- see PROJECT.md\n%% /refdocs %%\n",
            to: ctx.root, rel: "templates/macos/CLAUDE.md")

        let migrated = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated == ["macos", "templates/CLAUDE.md"])
        #expect(read(ctx.root, "templates/CLAUDE.md") == "# <<<PROJECT_NAME>>>\n\n## Reference docs\n")
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "## Reference docs\n- see PROJECT.md\n")
    }

    @Test("After migration the layer merges under the skeleton heading it used to fill")
    func migratedLayerMergesByHeading() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("%% BUILD AND TEST %%\n- run it", to: ctx.root, rel: "templates/macos/CLAUDE.md")
        _ = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        let layer = try #require(read(ctx.root, "templates/macos/CLAUDE.md"))
        let merged = MarkdownSectionMerge.merge(variants: ["## Build and test\n", layer])
        #expect(merged == "## Build and test\n- run it")
    }

    @Test("A legacy block still finds its custom heading after the skeleton was migrated")
    func mixedStateLayerFollowsMigratedSkeletonHeading() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        // Skeleton already migrated (placeholder gone, heading kept); the layer is not.
        try write("# <<<PROJECT_NAME>>>\n\n## Custom\n", to: ctx.root, rel: "templates/CLAUDE.md")
        try write(
            "%% CUSTOM %%\n- see docs\n%% /CUSTOM %%\n", to: ctx.root,
            rel: "templates/macos/CLAUDE.md")

        let migrated = TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated == ["macos"])
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "## Custom\n- see docs\n")
    }

    @Test("No store at the override root is a no-op")
    func emptyStoreNoOp() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        #expect(TemplateLayerFormatMigration.migrate(overrideRoot: ctx.root).isEmpty)
    }
}
