import Foundation
import Testing

@testable import Plumage

@Suite("LooseFileScopeMigration (#00078)")
struct LooseFileScopeMigrationTests {
    private func makeCtx() -> (
        overrideRoot: URL, store: TemplateCatalogStore, cleanup: () -> Void
    ) {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "LooseMig-\(UUID().uuidString)", directoryHint: .isDirectory)
        let overrideRoot = base.appending(path: "override", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
        let store = TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json"))
        return (overrideRoot, store, { try? FileManager.default.removeItem(at: base) })
    }

    private func write(_ contents: String, to root: URL, rel: String) throws {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ root: URL, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: rel).path)
    }

    // Persist a manifest where swift-shared carries a legacy `.skill` membership.
    private func seedLegacySkill(_ store: TemplateCatalogStore, _ skill: String) throws {
        var catalog = TemplateCatalog.bundledDefault
        catalog.addFile(toComponentID: "swift-shared", kind: .skill, fileName: skill)
        try store.save(catalog)
    }

    @Test("A legacy component skill moves into the component subtree and loses its membership")
    func migratesComponentSkill() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedLegacySkill(ctx.store, "legacy")
        try write("# Legacy", to: ctx.overrideRoot, rel: "skills/legacy/SKILL.md")
        try write("ref", to: ctx.overrideRoot, rel: "skills/legacy/reference.md")

        let moved = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(moved == ["swift-shared/legacy"])
        #expect(!exists(ctx.overrideRoot, "skills/legacy/SKILL.md"))
        #expect(exists(ctx.overrideRoot, "components/swift-shared/skills/legacy/SKILL.md"))
        #expect(exists(ctx.overrideRoot, "components/swift-shared/skills/legacy/reference.md"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .skill).contains("legacy") == false)
    }

    @Test("A skill shared by two components copies into both and drops the global source")
    func sharedSkillReachesEveryMember() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        var catalog = TemplateCatalog.bundledDefault
        catalog.addFile(toComponentID: "swift-shared", kind: .skill, fileName: "shared")
        catalog.addFile(toComponentID: "apple-shared", kind: .skill, fileName: "shared")
        try ctx.store.save(catalog)
        try write("# Shared", to: ctx.overrideRoot, rel: "skills/shared/SKILL.md")

        let moved = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(moved == ["apple-shared/shared", "swift-shared/shared"])
        // Both members own a copy; the global copy is gone (no longer leaks to all).
        #expect(exists(ctx.overrideRoot, "components/swift-shared/skills/shared/SKILL.md"))
        #expect(exists(ctx.overrideRoot, "components/apple-shared/skills/shared/SKILL.md"))
        #expect(!exists(ctx.overrideRoot, "skills/shared/SKILL.md"))
        let after = ctx.store.load()
        #expect(after.sharedComponent(id: "swift-shared")?.files(ofKind: .skill).isEmpty == true)
        #expect(after.sharedComponent(id: "apple-shared")?.files(ofKind: .skill).isEmpty == true)
    }

    @Test("An already-present destination still drops the membership and the global copy")
    func destinationAlreadyPresent() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedLegacySkill(ctx.store, "legacy")
        try write("# Legacy", to: ctx.overrideRoot, rel: "skills/legacy/SKILL.md")
        try write("# Owned", to: ctx.overrideRoot, rel: "components/swift-shared/skills/legacy/SKILL.md")

        let moved = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(moved == ["swift-shared/legacy"])
        #expect(!exists(ctx.overrideRoot, "skills/legacy/SKILL.md"))  // global copy dropped
        // The pre-existing destination is preserved verbatim, not clobbered.
        #expect(
            try String(
                contentsOf: ctx.overrideRoot.appending(
                    path: "components/swift-shared/skills/legacy/SKILL.md"), encoding: .utf8) == "# Owned")
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?.files(ofKind: .skill).isEmpty == true)
    }

    @Test("Running twice is a no-op the second time")
    func idempotent() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedLegacySkill(ctx.store, "legacy")
        try write("# Legacy", to: ctx.overrideRoot, rel: "skills/legacy/SKILL.md")

        _ = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)
        let second = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(second.isEmpty)
        #expect(exists(ctx.overrideRoot, "components/swift-shared/skills/legacy/SKILL.md"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?.files(ofKind: .skill).isEmpty == true)
    }

    @Test("Global loose files without a membership are left untouched (Base scope)")
    func noopWithoutMembership() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try write("# Plain", to: ctx.overrideRoot, rel: "skills/plain/SKILL.md")
        try write("# Doc", to: ctx.overrideRoot, rel: "docs/guide.md")

        let moved = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(moved.isEmpty)
        #expect(exists(ctx.overrideRoot, "skills/plain/SKILL.md"))
        #expect(exists(ctx.overrideRoot, "docs/guide.md"))
        #expect(!exists(ctx.overrideRoot, "components/swift-shared/skills/plain/SKILL.md"))
    }

    @Test("A membership with no physical source leaves the manifest untouched")
    func manifestUntouchedWhenSourceMissing() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedLegacySkill(ctx.store, "ghost")

        let moved = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        #expect(moved.isEmpty)
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .skill).contains("ghost") == true)
    }

    @Test("Composition stays byte-identical across the migration")
    func compositionByteIdentical() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedLegacySkill(ctx.store, "legacy")
        try write("# Legacy", to: ctx.overrideRoot, rel: "skills/legacy/SKILL.md")

        _ = LooseFileScopeMigration.migrate(overrideRoot: ctx.overrideRoot, store: ctx.store)

        let after = ctx.store.load()
        let bundled = TemplateCatalog.bundledDefault
        for kind in ProjectKind.allCases {
            #expect(
                after.effectiveLayers(forTemplate: kind.rawValue)
                    == bundled.effectiveLayers(forTemplate: kind.rawValue))
            #expect(
                after.effectiveHooks(forTemplate: kind.rawValue)
                    == bundled.effectiveHooks(forTemplate: kind.rawValue))
        }
    }
}
