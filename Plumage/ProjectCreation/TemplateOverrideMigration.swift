import Foundation

// One-time migration of the per-user override store to the folder-per-layer layout
// (#00071 / decision D1): a flat layer override `templates/<layer>.md` moves to
// `templates/<layer>/CLAUDE.md`, matching where the composer now reads it. Without
// this, an upgrading user's saved layer edits would be silently ignored.
//
// Pure file I/O so it is testable and safe to run off-main at launch. The base
// skeleton `templates/CLAUDE.md` is intentionally left flat. Idempotent and
// lossless: a file moves only when its folder form does not yet exist; a missing
// source or an already-migrated target is a no-op.
nonisolated enum TemplateOverrideMigration {
    // Runs the migration against the standard override store, if one is reachable.
    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(overrideRoot: root)
    }

    // Migrates the override store rooted at `overrideRoot`. Returns the layer names
    // that were moved (empty when there was nothing to do).
    @discardableResult
    static func migrate(overrideRoot: URL) -> [String] {
        let fileManager = FileManager.default
        let templatesDir = overrideRoot.appending(path: "templates", directoryHint: .isDirectory)
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: templatesDir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }

        var migrated: [String] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                entry.pathExtension == "md",
                entry.lastPathComponent != "CLAUDE.md"  // the base skeleton stays flat
            else { continue }
            let layer = entry.deletingPathExtension().lastPathComponent
            let targetDir = templatesDir.appending(path: layer, directoryHint: .isDirectory)
            let target = targetDir.appending(path: "CLAUDE.md")
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
                try fileManager.moveItem(at: entry, to: target)
                migrated.append(layer)
            } catch {
                continue
            }
        }
        return migrated.sorted()
    }
}
