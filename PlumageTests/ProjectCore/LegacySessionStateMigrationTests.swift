import Foundation
import Testing

@testable import Plumage

struct LegacySessionStateMigrationTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeLegacyChatID(_ id: String, under root: URL) throws {
        let dir =
            root
            .appendingPathComponent(".plumage", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try id.write(to: dir.appendingPathComponent("chat-id"), atomically: true, encoding: .utf8)
    }

    @Test("moves a leftover chat-id from the legacy dotfolder into the bundle")
    func migratesChatID() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("App.plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try writeLegacyChatID("abc-123", under: root)

        LegacySessionStateMigration.migrate(root: root, bundle: bundle)

        let dest = bundle.appendingPathComponent("sessions/chat-id")
        let moved = try String(contentsOf: dest, encoding: .utf8)
        #expect(moved == "abc-123")
        // The legacy file is moved, not copied.
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".plumage/sessions/chat-id").path))
    }

    @Test("never clobbers an existing chat-id already in the bundle")
    func doesNotClobber() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("App.plumage", isDirectory: true)
        let destDir = bundle.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "current".write(
            to: destDir.appendingPathComponent("chat-id"), atomically: true, encoding: .utf8)
        try writeLegacyChatID("legacy", under: root)

        LegacySessionStateMigration.migrate(root: root, bundle: bundle)

        let kept = try String(contentsOf: destDir.appendingPathComponent("chat-id"), encoding: .utf8)
        #expect(kept == "current")
    }

    @Test("no-op when root and bundle are the same (resolution fell back to root)")
    func noOpWhenRootEqualsBundle() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLegacyChatID("abc", under: root)

        LegacySessionStateMigration.migrate(root: root, bundle: root)

        // Legacy file untouched; nothing to migrate into.
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".plumage/sessions/chat-id").path))
    }

    @Test("no-op when there is no legacy chat-id")
    func noOpWhenNoLegacy() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("App.plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        LegacySessionStateMigration.migrate(root: root, bundle: bundle)

        #expect(
            !FileManager.default.fileExists(atPath: bundle.appendingPathComponent("sessions").path))
    }
}
