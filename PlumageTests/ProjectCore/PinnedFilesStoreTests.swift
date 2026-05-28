import Foundation
import Testing

@testable import Plumage

@Suite("PinnedFilesStore")
struct PinnedFilesStoreTests {
    // A project root with a `Test.plumage` bundle inside it. The bundle is the
    // directory pins.json lives in; the root is what seedDefaults resolves
    // CLAUDE.md / PROJECT.md against.
    private final class Fixture {
        let root: URL
        let bundle: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("PlumagePinsStore-\(UUID().uuidString)", isDirectory: true)
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

    @Test("load returns nil when pins.json is absent")
    func loadMissingReturnsNil() throws {
        let fixture = try Fixture()
        #expect(PinnedFilesStore.load(bundle: fixture.bundle) == nil)
    }

    @Test("load returns the saved list when present")
    func loadPresentReturnsList() throws {
        let fixture = try Fixture()
        try PinnedFilesStore.save([".claude/CLAUDE.md", "CLAUDE.md"], bundle: fixture.bundle)
        #expect(PinnedFilesStore.load(bundle: fixture.bundle) == [".claude/CLAUDE.md", "CLAUDE.md"])
    }

    @Test("save/load round-trips and preserves pin order")
    func saveRoundTripPreservesOrder() throws {
        let fixture = try Fixture()
        let paths = ["b.md", "a.md", ".claude/docs/PROJECT.md", ".mcp.json"]
        try PinnedFilesStore.save(paths, bundle: fixture.bundle)
        #expect(PinnedFilesStore.load(bundle: fixture.bundle) == paths)
    }

    @Test("corrupt pins.json loads as empty, not nil (no reseed)")
    func corruptLoadsAsEmpty() throws {
        let fixture = try Fixture()
        let url = fixture.bundle.appendingPathComponent(PinnedFilesStore.fileName)
        try "{ this is not json".write(to: url, atomically: true, encoding: .utf8)
        // Present-but-empty (not nil): distinguishes corrupt from "never seeded".
        #expect(PinnedFilesStore.load(bundle: fixture.bundle)?.isEmpty == true)
    }

    @Test("seedDefaults uses root CLAUDE.md when present")
    func seedRootClaude() throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: "CLAUDE.md")
        #expect(PinnedFilesStore.seedDefaults(projectURL: fixture.root) == ["CLAUDE.md"])
    }

    @Test("seedDefaults falls back to .claude/CLAUDE.md when root is absent")
    func seedNestedClaudeFallback() throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: ".claude/CLAUDE.md")
        #expect(PinnedFilesStore.seedDefaults(projectURL: fixture.root) == [".claude/CLAUDE.md"])
    }

    @Test("seedDefaults prefers root CLAUDE.md over .claude/CLAUDE.md")
    func seedPrefersRootClaude() throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: "CLAUDE.md")
        try fixture.makeFile(at: ".claude/CLAUDE.md")
        #expect(PinnedFilesStore.seedDefaults(projectURL: fixture.root) == ["CLAUDE.md"])
    }

    @Test("seedDefaults includes PROJECT.md and orders CLAUDE before PROJECT")
    func seedBothDefaults() throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: "CLAUDE.md")
        try fixture.makeFile(at: ".claude/docs/PROJECT.md")
        #expect(
            PinnedFilesStore.seedDefaults(projectURL: fixture.root)
                == ["CLAUDE.md", ".claude/docs/PROJECT.md"])
    }

    @Test("seedDefaults returns empty when neither default exists")
    func seedNoneExist() throws {
        let fixture = try Fixture()
        #expect(PinnedFilesStore.seedDefaults(projectURL: fixture.root).isEmpty)
    }

    @Test("seedDefaults skips a missing default rather than producing a dead pin")
    func seedSkipsMissing() throws {
        let fixture = try Fixture()
        try fixture.makeFile(at: ".claude/docs/PROJECT.md")
        // No CLAUDE.md anywhere → only PROJECT.md is seeded.
        #expect(
            PinnedFilesStore.seedDefaults(projectURL: fixture.root)
                == [".claude/docs/PROJECT.md"])
    }
}
