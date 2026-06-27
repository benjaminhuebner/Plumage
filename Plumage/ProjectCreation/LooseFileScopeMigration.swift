import Foundation
import os

// One-time migration: previously a component's skill was the shared global
// `skills/<name>/` tracked by a `.skill` membership; the new model makes each component
// own its copy under `components/<id>/skills/`. Only membership-backed component skills
// move — global loose files and composition assets are deliberately left untouched, since
// they were never the leak this fixes. Runs off-main after `TemplateOverrideMigration`
// (it depends on the layout that migration establishes).
nonisolated enum LooseFileScopeMigration {
    private static let logger = Logger(subsystem: "com.plumage", category: "LooseFileScopeMigration")

    // Runs against the standard override store and catalog manifest, if reachable.
    @discardableResult
    static func migrateStandard() -> [String] {
        guard let root = ScaffoldOverrides.standardOverrideRoot() else { return [] }
        return migrate(overrideRoot: root, store: TemplateCatalogStore())
    }

    // A single global skill could be referenced by several components, so each member
    // *copies* the folder (a move would strand the next member) and the global copy is
    // dropped only once every member owns one — otherwise it would keep leaking into all
    // templates as a Base skill. A membership whose source is missing is left untouched.
    @discardableResult
    static func migrate(overrideRoot: URL, store: TemplateCatalogStore) -> [String] {
        let fileManager = FileManager.default
        // A corrupt manifest is left untouched: migrating the bundled fallback over it
        // would overwrite the user's structure on the next save (the manager warns instead).
        let loaded = store.loadDiagnosed()
        guard !loaded.corrupt else { return [] }
        var catalog = loaded.catalog
        var moved: [String] = []

        // Group the legacy memberships by skill name so a shared skill is handled once.
        var membersBySkill: [String: [String]] = [:]
        for component in catalog.sharedComponents {
            for skill in component.files(ofKind: .skill) {
                membersBySkill[skill, default: []].append(component.id)
            }
        }

        for (skill, componentIDs) in membersBySkill {
            let source = overrideRoot.appending(path: "skills/\(skill)", directoryHint: .isDirectory)
            // No physical source: a membership we can't fulfil — leave it as-is.
            guard fileManager.fileExists(atPath: source.path) else { continue }

            for componentID in componentIDs {
                let destDir = overrideRoot.appending(
                    path: "components/\(componentID)/skills", directoryHint: .isDirectory)
                let dest = destDir.appending(path: skill, directoryHint: .isDirectory)
                if !fileManager.fileExists(atPath: dest.path) {
                    do {
                        try fileManager.createDirectory(
                            at: destDir, withIntermediateDirectories: true)
                        try fileManager.copyItem(at: source, to: dest)
                    } catch {
                        continue  // leave this membership in place on a failed copy; retried next launch
                    }
                }
                catalog.removeFile(fromComponentID: componentID, kind: .skill, fileName: skill)
                moved.append("\(componentID)/\(skill)")
            }
            // Drop the global source only once every member owns an identical copy — a
            // pre-existing but divergent dest must not let the user's source be removed.
            let everyMemberHasVerifiedCopy = componentIDs.allSatisfy { componentID in
                let dest = overrideRoot.appending(
                    path: "components/\(componentID)/skills/\(skill)", directoryHint: .isDirectory)
                return fileManager.contentsEqual(atPath: source.path, andPath: dest.path)
            }
            if everyMemberHasVerifiedCopy {
                do {
                    try fileManager.removeItem(at: source)
                } catch {
                    Self.logger.warning(
                        "couldn't remove migrated skill source \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        if !moved.isEmpty {
            do {
                try store.save(catalog)
            } catch {
                Self.logger.warning(
                    "couldn't persist skill migration: \(error.localizedDescription, privacy: .public)")
            }
        }
        return moved.sorted()
    }
}
