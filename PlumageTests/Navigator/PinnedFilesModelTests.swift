import Foundation
import Testing

@testable import Plumage

@Suite("PinnedFilesModel")
@MainActor
struct PinnedFilesModelTests {
    // Project root with a `Test.plumage` bundle, so BundleResolver.resolve
    // succeeds and persistence/seed paths can be exercised.
    private final class Fixture {
        let root: URL
        let bundle: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("PlumagePinsModel-\(UUID().uuidString)", isDirectory: true)
            bundle = root.appendingPathComponent("Test.plumage", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func makeFile(at relativePath: String, content: String = "x") throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @Test("pin appends and unpin removes")
    func pinUnpin() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()

        model.pin(relativePath: "CLAUDE.md", projectURL: fixture.root)
        #expect(model.pinned == ["CLAUDE.md"])
        #expect(model.contains("CLAUDE.md"))

        model.unpin(relativePath: "CLAUDE.md", projectURL: fixture.root)
        #expect(model.pinned.isEmpty)
        #expect(!model.contains("CLAUDE.md"))
    }

    @Test("pin is idempotent and preserves insertion order")
    func pinIdempotentOrdered() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()

        model.pin(relativePath: "a.md", projectURL: fixture.root)
        model.pin(relativePath: "b.md", projectURL: fixture.root)
        model.pin(relativePath: "a.md", projectURL: fixture.root)  // duplicate no-op

        #expect(model.pinned == ["a.md", "b.md"])
    }

    @Test("loadOrSeed seeds defaults and persists when pins.json is absent")
    func loadOrSeedSeedsOnFirstLoad() async throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: "CLAUDE.md")
        try fixture.makeFile(at: ".claude/docs/PROJECT.md")
        let model = PinnedFilesModel()

        await model.loadOrSeed(projectURL: fixture.root)

        #expect(model.pinned == ["CLAUDE.md", ".claude/docs/PROJECT.md"])
        // Seed was persisted (write happens inside the awaited detached task).
        #expect(PinnedFilesStore.load(bundle: fixture.bundle) == ["CLAUDE.md", ".claude/docs/PROJECT.md"])
    }

    @Test("loadOrSeed seeds nested .claude/CLAUDE.md + PROJECT.md (no root CLAUDE.md)")
    func loadOrSeedSeedsNestedClaude() async throws {
        // Mirrors Plumage's own project shape: no root CLAUDE.md, but
        // .claude/CLAUDE.md and .claude/docs/PROJECT.md both present.
        let fixture = try Fixture()
        try fixture.makeFile(at: ".claude/CLAUDE.md")
        try fixture.makeFile(at: ".claude/docs/PROJECT.md")
        let model = PinnedFilesModel()

        await model.loadOrSeed(projectURL: fixture.root)

        #expect(model.pinned == [".claude/CLAUDE.md", ".claude/docs/PROJECT.md"])
        #expect(
            PinnedFilesStore.load(bundle: fixture.bundle)
                == [".claude/CLAUDE.md", ".claude/docs/PROJECT.md"])
    }

    @Test("loadOrSeed does not reseed a present-but-empty file")
    func loadOrSeedNoReseedWhenEmpty() async throws {
        let fixture = try Fixture()
        // CLAUDE.md exists, but the user already unpinned everything.
        try fixture.makeFile(at: "CLAUDE.md")
        try PinnedFilesStore.save([], bundle: fixture.bundle)
        let model = PinnedFilesModel()

        await model.loadOrSeed(projectURL: fixture.root)

        #expect(model.pinned.isEmpty)
        // File stays empty — no reseed overwrote it.
        #expect(PinnedFilesStore.load(bundle: fixture.bundle)?.isEmpty == true)
    }

    @Test("loadOrSeed loads an existing non-empty pin set verbatim")
    func loadOrSeedLoadsExisting() async throws {
        let fixture = try Fixture()
        try PinnedFilesStore.save([".mcp.json", "CLAUDE.md"], bundle: fixture.bundle)
        let model = PinnedFilesModel()

        await model.loadOrSeed(projectURL: fixture.root)

        #expect(model.pinned == [".mcp.json", "CLAUDE.md"])
    }

    @Test("apply re-points an exact moved pin")
    func applyMovedExact() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()
        model.pin(relativePath: ".claude/docs/foo.md", projectURL: fixture.root)

        model.apply(rewrites: [
            .moved(oldRelativePath: ".claude/docs/foo.md", newRelativePath: ".claude/docs/bar.md")
        ])

        #expect(model.pinned == [".claude/docs/bar.md"])
    }

    @Test("apply re-points a pin under a moved folder")
    func applyMovedDescendant() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()
        model.pin(relativePath: ".claude/docs/PROJECT.md", projectURL: fixture.root)

        model.apply(rewrites: [
            .moved(oldRelativePath: ".claude/docs", newRelativePath: ".claude/documents")
        ])

        #expect(model.pinned == [".claude/documents/PROJECT.md"])
    }

    @Test("apply removes an exact removed pin")
    func applyRemovedExact() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()
        model.pin(relativePath: "CLAUDE.md", projectURL: fixture.root)
        model.pin(relativePath: ".mcp.json", projectURL: fixture.root)

        model.apply(rewrites: [.removed(oldRelativePath: "CLAUDE.md")])

        #expect(model.pinned == [".mcp.json"])
    }

    @Test("apply removes pins under a removed folder")
    func applyRemovedDescendant() throws {
        let fixture = try Fixture()
        let model = PinnedFilesModel()
        model.pin(relativePath: ".claude/docs/PROJECT.md", projectURL: fixture.root)

        model.apply(rewrites: [.removed(oldRelativePath: ".claude/docs")])

        #expect(model.pinned.isEmpty)
    }

    @Test("pruneMissing drops pins whose file no longer exists")
    func pruneMissingDropsGoneFiles() async throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: ".claude/docs/here.md")
        try fixture.makeFile(at: ".claude/docs/gone.md")
        let model = PinnedFilesModel()
        model.pin(relativePath: ".claude/docs/here.md", projectURL: fixture.root)
        model.pin(relativePath: ".claude/docs/gone.md", projectURL: fixture.root)

        try FileManager.default.removeItem(
            at: fixture.root.appendingPathComponent(".claude/docs/gone.md"))
        await model.pruneMissing(projectURL: fixture.root)

        #expect(model.pinned == [".claude/docs/here.md"])
    }
}
