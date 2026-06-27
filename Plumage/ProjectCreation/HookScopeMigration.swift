import Foundation
import os

// One-time migration: component-member user hooks move from the shared global
// `hooks/` into `components/<id>/hooks/`. Built-in memberships and unowned global
// hooks (= Base ownership) stay untouched. Runs off-main after `LooseFileScopeMigration`.
nonisolated enum HookScopeMigration {
    private static let logger = Logger(subsystem: "com.plumage", category: "HookScopeMigration")

    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(
            overrideRoot: root, bundledRoot: NewProjectAssets.bundledRoot,
            store: TemplateCatalogStore())
    }

    // Memberships are base-named; the file resolves by stem. A multi-member hook is
    // copied to each member, the global file dropped once every member owns a copy.
    // A membership whose source file is gone is stale (interrupted run) and dropped.
    @discardableResult
    static func migrate(overrideRoot: URL, bundledRoot: URL, store: TemplateCatalogStore) -> [String] {
        let fileManager = FileManager.default
        // A corrupt manifest is left untouched: migrating the bundled fallback over it
        // would overwrite the user's structure on the next save (the manager warns instead).
        let loaded = store.loadDiagnosed()
        guard !loaded.corrupt else { return [] }
        var catalog = loaded.catalog
        var moved: [String] = []
        var catalogChanged = false

        let bundledStems = Set(
            ((try? fileManager.contentsOfDirectory(atPath: bundledRoot.appending(path: "hooks").path))
                ?? [])
                .filter { !ScaffoldOverrides.isNoise($0) }
                .map { ($0 as NSString).deletingPathExtension })
        let globalHookFiles =
            (try? fileManager.contentsOfDirectory(atPath: overrideRoot.appending(path: "hooks").path))
            ?? []

        // Group the legacy memberships by hook base name so a shared hook is handled once.
        var membersByBase: [String: [(componentID: String, storedName: String)]] = [:]
        for component in catalog.sharedComponents {
            for storedName in component.files(ofKind: .hook) {
                let base = (storedName as NSString).deletingPathExtension
                guard !bundledStems.contains(base) else { continue }  // built-in declaration
                membersByBase[base, default: []].append((component.id, storedName))
            }
        }

        for (base, members) in membersByBase {
            let fileName =
                globalHookFiles.first { ($0 as NSString).deletingPathExtension == base }
            guard let fileName else {
                // No physical source: an interrupted earlier run already moved (or the
                // user deleted) the file — the membership is stale, drop it.
                for member in members {
                    catalog.removeFile(
                        fromComponentID: member.componentID, kind: .hook, fileName: member.storedName)
                    catalogChanged = true
                }
                continue
            }
            let source = overrideRoot.appending(path: "hooks/\(fileName)")

            for member in members {
                let destDir = overrideRoot.appending(
                    path: "components/\(member.componentID)/hooks", directoryHint: .isDirectory)
                let dest = destDir.appending(path: fileName)
                if !fileManager.fileExists(atPath: dest.path) {
                    do {
                        try fileManager.createDirectory(
                            at: destDir, withIntermediateDirectories: true)
                        try fileManager.copyItem(at: source, to: dest)
                    } catch {
                        continue  // leave this membership in place on a failed copy; retried next launch
                    }
                }
                catalog.removeFile(
                    fromComponentID: member.componentID, kind: .hook, fileName: member.storedName)
                catalogChanged = true
                moved.append("\(member.componentID)/\(fileName)")
            }
            // Drop the global source only once every member owns a byte-identical copy — a
            // pre-existing but divergent dest must not let the user's source be removed.
            let everyMemberHasVerifiedCopy = members.allSatisfy { member in
                let dest = overrideRoot.appending(
                    path: "components/\(member.componentID)/hooks/\(fileName)")
                return fileManager.contentsEqual(atPath: source.path, andPath: dest.path)
            }
            if everyMemberHasVerifiedCopy {
                do {
                    try fileManager.removeItem(at: source)
                } catch {
                    Self.logger.warning(
                        "couldn't remove migrated hook source \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        if catalogChanged {
            do {
                try store.save(catalog)
            } catch {
                Self.logger.warning(
                    "couldn't persist hook migration: \(error.localizedDescription, privacy: .public)")
            }
        }
        return moved.sorted()
    }
}
