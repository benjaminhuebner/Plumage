import Foundation

// Renames a Plumage project: moves the `<name>.plumage` bundle folder on disk
// and rewrites `config.name` so the display name and the folder stay in sync.
// The project root (the user's git working dir) is deliberately left alone —
// renaming it would break window identity, the subprocess cwd, the Recents URL
// and the per-cwd Claude session-log key (#00077).
//
// nonisolated + static-throws, mirroring IssueArchiver / ConfigWriter: the
// caller offloads it off the main actor.
nonisolated enum ProjectRenamer {
    enum RenameError: Error, Equatable, Sendable {
        case invalidName
        case resolveFailed(message: String)
        case bundleExists(URL)
        case moveFailed(message: String)
        case configWriteFailed(message: String)
    }

    // Same rule as MigrateProjectModel.isValidName: a bundle folder name must be
    // a single, non-empty path component. Kept here so a rename can validate
    // without reaching into the migrate UI module.
    static func isValidName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
    }

    // Transactional, fail-safe: validate → resolve current bundle → move folder
    // → write config.name. A config-write failure after a successful move rolls
    // the move back so disk is never left half-renamed. Returns the new bundle
    // URL. No-op move when the folder is already named `<newName>.plumage`
    // (still rewrites config.name to repair a Finder-renamed bundle whose
    // config.name drifted — the #00010 legacy case).
    @discardableResult
    static func rename(projectRoot: URL, newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw RenameError.invalidName }

        let fm = FileManager.default
        let oldBundle: URL
        do {
            oldBundle = try BundleResolver.findBundle(in: projectRoot)
        } catch {
            throw RenameError.resolveFailed(message: error.localizedDescription)
        }

        let target = projectRoot.appendingPathComponent(
            "\(trimmed).\(BundleResolver.bundleExtension)", isDirectory: true)

        let didMove: Bool
        if target.standardizedFileURL == oldBundle.standardizedFileURL {
            didMove = false
        } else {
            guard !fm.fileExists(atPath: target.path) else {
                throw RenameError.bundleExists(target)
            }
            do {
                try fm.moveItem(at: oldBundle, to: target)
            } catch {
                throw RenameError.moveFailed(message: error.localizedDescription)
            }
            didMove = true
        }

        do {
            try ConfigWriter.writeName(trimmed, atBundle: target)
        } catch {
            if didMove {
                // Best-effort rollback so a failed config write leaves the
                // bundle where it started rather than half-renamed.
                try? fm.moveItem(at: target, to: oldBundle)
            }
            throw RenameError.configWriteFailed(message: error.localizedDescription)
        }

        return target
    }
}
