import Foundation
import Testing

@testable import Plumage

@Suite("TemplateOverrideMigration")
struct TemplateOverrideMigrationTests {
    private func makeStore() -> (root: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Migrate-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    private func exists(_ root: URL, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: rel).path)
    }

    @Test("A flat layer override moves to the folder form, content preserved")
    func migratesFlatLayer() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("MACOS-EDIT", to: ctx.root, rel: "templates/macos.md")

        let migrated = TemplateOverrideMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated == ["macos"])
        #expect(!exists(ctx.root, "templates/macos.md"))
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "MACOS-EDIT")
    }

    @Test("The base skeleton templates/CLAUDE.md is left flat")
    func leavesBaseSkeleton() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("# <<<PROJECT_NAME>>>", to: ctx.root, rel: "templates/CLAUDE.md")

        let migrated = TemplateOverrideMigration.migrate(overrideRoot: ctx.root)

        #expect(migrated.isEmpty)
        #expect(exists(ctx.root, "templates/CLAUDE.md"))
        #expect(!exists(ctx.root, "templates/CLAUDE/CLAUDE.md"))
    }

    @Test("Migration is idempotent and never overwrites an existing folder form")
    func idempotentAndNonDestructive() throws {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        try write("OLD-FLAT", to: ctx.root, rel: "templates/ios.md")
        try write("NEW-FOLDER", to: ctx.root, rel: "templates/macos/CLAUDE.md")
        try write("FLAT-MACOS", to: ctx.root, rel: "templates/macos.md")

        let first = TemplateOverrideMigration.migrate(overrideRoot: ctx.root)
        let second = TemplateOverrideMigration.migrate(overrideRoot: ctx.root)

        #expect(first == ["ios"])  // macos folder already exists → its flat file is not moved
        #expect(second.isEmpty)  // nothing left to migrate
        #expect(read(ctx.root, "templates/ios/CLAUDE.md") == "OLD-FLAT")
        #expect(read(ctx.root, "templates/macos/CLAUDE.md") == "NEW-FOLDER")  // never overwritten
    }

    @Test("A missing templates directory is a no-op")
    func missingDirNoop() {
        let ctx = makeStore()
        defer { ctx.cleanup() }
        #expect(TemplateOverrideMigration.migrate(overrideRoot: ctx.root).isEmpty)
    }
}
