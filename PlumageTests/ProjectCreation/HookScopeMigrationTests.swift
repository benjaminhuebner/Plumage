import Foundation
import Testing

@testable import Plumage

@Suite("HookScopeMigration")
struct HookScopeMigrationTests {
    private func makeCtx() -> (
        overrideRoot: URL, store: TemplateCatalogStore, cleanup: () -> Void
    ) {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "HookMig-\(UUID().uuidString)", directoryHint: .isDirectory)
        let overrideRoot = base.appending(path: "override", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
        let store = TemplateCatalogStore(manifestURL: base.appending(path: "manifest.json"))
        return (overrideRoot, store, { try? FileManager.default.removeItem(at: base) })
    }

    private func migrate(
        _ ctx: (overrideRoot: URL, store: TemplateCatalogStore, cleanup: () -> Void)
    )
        -> [String]
    {
        HookScopeMigration.migrate(
            overrideRoot: ctx.overrideRoot, bundledRoot: RepoAssets.root, store: ctx.store)
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

    private func seedMemberHook(
        _ store: TemplateCatalogStore, component: String = "swift-shared", name: String
    ) throws {
        var catalog = store.load()
        catalog.addFile(toComponentID: component, kind: .hook, fileName: name)
        try store.save(catalog)
    }

    @Test("A component-member user hook moves into the component subtree and loses its membership")
    func migratesComponentHook() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")

        let moved = migrate(ctx)

        #expect(moved == ["swift-shared/my-hook.sh"])
        #expect(!exists(ctx.overrideRoot, "hooks/my-hook.sh"))
        #expect(exists(ctx.overrideRoot, "components/swift-shared/hooks/my-hook.sh"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-hook") == false)
    }

    @Test("A non-Bash hook moves under its real filename, resolved by stem")
    func migratesPythonHookByStem() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "py-hook")
        try write("#!/usr/bin/env python3\n", to: ctx.overrideRoot, rel: "hooks/py-hook.py")

        let moved = migrate(ctx)

        #expect(moved == ["swift-shared/py-hook.py"])
        #expect(exists(ctx.overrideRoot, "components/swift-shared/hooks/py-hook.py"))
        #expect(!exists(ctx.overrideRoot, "hooks/py-hook.py"))
    }

    @Test("Built-in hook memberships are left untouched, including a content override")
    func builtInMembershipUntouched() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        // A content override of a bundled built-in hook must stay the global slot.
        try write("#!/bin/sh\n# custom\n", to: ctx.overrideRoot, rel: "hooks/format-swift.sh")

        let moved = migrate(ctx)

        #expect(moved.isEmpty)
        #expect(exists(ctx.overrideRoot, "hooks/format-swift.sh"))
        #expect(!exists(ctx.overrideRoot, "components/swift-shared/hooks/format-swift.sh"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("format-swift") == true)
    }

    @Test("A hook referenced by two components copies into both and drops the global source")
    func sharedHookReachesEveryMember() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        var catalog = ctx.store.load()
        catalog.addFile(toComponentID: "swift-shared", kind: .hook, fileName: "shared-hook")
        catalog.addFile(toComponentID: "apple-shared", kind: .hook, fileName: "shared-hook")
        try ctx.store.save(catalog)
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/shared-hook.sh")

        let moved = migrate(ctx)

        #expect(moved == ["apple-shared/shared-hook.sh", "swift-shared/shared-hook.sh"])
        #expect(exists(ctx.overrideRoot, "components/swift-shared/hooks/shared-hook.sh"))
        #expect(exists(ctx.overrideRoot, "components/apple-shared/hooks/shared-hook.sh"))
        #expect(!exists(ctx.overrideRoot, "hooks/shared-hook.sh"))
        let after = ctx.store.load()
        #expect(after.sharedComponent(id: "swift-shared")?.files(ofKind: .hook).contains("shared-hook") == false)
        #expect(after.sharedComponent(id: "apple-shared")?.files(ofKind: .hook).contains("shared-hook") == false)
    }

    @Test("Running twice is a no-op the second time")
    func idempotent() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")

        _ = migrate(ctx)
        let second = migrate(ctx)

        #expect(second.isEmpty)
        #expect(exists(ctx.overrideRoot, "components/swift-shared/hooks/my-hook.sh"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-hook") == false)
    }

    @Test("Interrupted state (file already moved, membership still present) drops the membership")
    func interruptedRunDropsStaleMembership() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n# owned\n", to: ctx.overrideRoot, rel: "components/swift-shared/hooks/my-hook.sh")

        let moved = migrate(ctx)

        #expect(moved.isEmpty)
        // The already-moved copy is preserved verbatim, not clobbered.
        #expect(
            try String(
                contentsOf: ctx.overrideRoot.appending(
                    path: "components/swift-shared/hooks/my-hook.sh"), encoding: .utf8)
                == "#!/bin/sh\n# owned\n")
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-hook") == false)
    }

    @Test("An unowned global user hook stays in hooks/ (Base ownership)")
    func unownedHookStaysGlobal() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/base-hook.sh")

        let moved = migrate(ctx)

        #expect(moved.isEmpty)
        #expect(exists(ctx.overrideRoot, "hooks/base-hook.sh"))
    }

    @Test("Built-in hook resolution stays byte-identical across the migration")
    func effectiveHooksUnchanged() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")

        _ = migrate(ctx)

        let after = ctx.store.load()
        let bundled = TemplateCatalog.bundledDefault
        for kind in ProjectKind.allCases {
            #expect(
                after.effectiveHooks(forTemplate: kind.rawValue)
                    == bundled.effectiveHooks(forTemplate: kind.rawValue))
        }
    }

    @Test("A divergent pre-existing dest keeps the global source instead of removing it")
    func divergentDestKeepsSource() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n# SOURCE\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")
        try write(
            "#!/bin/sh\n# STALE\n", to: ctx.overrideRoot,
            rel: "components/swift-shared/hooks/my-hook.sh")

        _ = migrate(ctx)

        #expect(exists(ctx.overrideRoot, "hooks/my-hook.sh"))
        #expect(
            try String(
                contentsOf: ctx.overrideRoot.appending(path: "hooks/my-hook.sh"), encoding: .utf8)
                == "#!/bin/sh\n# SOURCE\n")
    }

    @Test("A corrupt manifest is left untouched by the migration")
    func corruptManifestSkipsMigration() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")
        let manifestURL = try #require(ctx.store.manifestURL)
        try Data("{ broken".utf8).write(to: manifestURL)

        let moved = migrate(ctx)

        #expect(moved.isEmpty)
        #expect(exists(ctx.overrideRoot, "hooks/my-hook.sh"))
        #expect(TemplateCatalogStore(manifestURL: manifestURL).loadDiagnosed().corrupt == true)
    }

    @Test("A failed copy keeps both the membership and the global source")
    func failedCopyKeepsMembershipAndSource() throws {
        let ctx = makeCtx()
        defer { ctx.cleanup() }
        try seedMemberHook(ctx.store, name: "my-hook")
        try write("#!/bin/sh\n", to: ctx.overrideRoot, rel: "hooks/my-hook.sh")
        // A file where the destination directory must go makes the copy throw.
        try write("x", to: ctx.overrideRoot, rel: "components/swift-shared/hooks")

        let moved = migrate(ctx)

        #expect(moved.isEmpty)
        #expect(exists(ctx.overrideRoot, "hooks/my-hook.sh"))
        #expect(
            ctx.store.load().sharedComponent(id: "swift-shared")?
                .files(ofKind: .hook).contains("my-hook") == true)
    }
}
