import Foundation

// One-time migration of user-authored component skills to scope ownership (#00078).
// Before #00078 a skill added to a Shared Component was tracked by a `.skill`
// `ComponentFile` while its bytes sat in the global `skills/<name>/`. The new model
// makes a component own its loose files under `components/<id>/`, so each such skill
// folder moves there and the redundant `.skill` membership is dropped.
//
// Everything else is intentionally left in place: global loose files (`docs/`,
// `agents/`, `skills/`, root files) are valid Base-scope files (no-op), and the
// composition assets (layer `CLAUDE.md`, hooks, `templates/<id>/CLAUDE.md`) never moved.
//
// Pure file I/O plus a manifest rewrite, so it is testable and safe to run off-main at
// launch *after* `TemplateOverrideMigration`. Idempotent and lossless: a skill moves
// only when its source exists and the target does not; the manifest is rewritten only
// when at least one skill actually moved, and only drops the memberships that moved (no
// orphaned edits) — so files move before the manifest changes, never leaving a dangling
// membership pointing at a moved folder.
nonisolated enum LooseFileScopeMigration {
    // Runs against the standard override store and catalog manifest, if reachable.
    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(overrideRoot: root, store: TemplateCatalogStore())
    }

    // Migrates the store rooted at `overrideRoot` against `store`'s manifest. Returns the
    // `<componentID>/<skillName>` pairs that were moved (empty when there was nothing to do).
    @discardableResult
    static func migrate(overrideRoot: URL, store: TemplateCatalogStore) -> [String] {
        let fileManager = FileManager.default
        var catalog = store.load()
        var moved: [String] = []

        for component in catalog.sharedComponents {
            for skill in component.files(ofKind: .skill) {
                let source = overrideRoot.appending(
                    path: "skills/\(skill)", directoryHint: .isDirectory)
                let destDir = overrideRoot.appending(
                    path: "components/\(component.id)/skills", directoryHint: .isDirectory)
                let dest = destDir.appending(path: skill, directoryHint: .isDirectory)
                // Already moved (target present) or nothing to move (source absent): skip,
                // and leave the manifest untouched.
                guard fileManager.fileExists(atPath: source.path),
                    !fileManager.fileExists(atPath: dest.path)
                else { continue }
                do {
                    try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try fileManager.moveItem(at: source, to: dest)
                } catch {
                    continue  // leave the membership in place on a failed move
                }
                catalog.removeFile(fromComponentID: component.id, kind: .skill, fileName: skill)
                moved.append("\(component.id)/\(skill)")
            }
        }

        if !moved.isEmpty { try? store.save(catalog) }
        return moved.sorted()
    }
}
