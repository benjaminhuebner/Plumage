import Foundation
import os

// Renames a Plumage project: moves the `<name>.plumage` bundle folder on disk
// and rewrites `config.name` so the display name and the folder stay in sync.
// The project root (the user's git working dir) is deliberately left alone —
// renaming it would break window identity, the subprocess cwd, the Recents URL
// and the per-cwd Claude session-log key.
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
    // config.name drifted — the legacy case).
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
            // Attempt-then-handle instead of exists-then-move: a pre-check
            // races concurrent writers creating the same target (TOCTOU).
            do {
                try fm.moveItem(at: oldBundle, to: target)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw RenameError.bundleExists(target)
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

        // Best-effort: repoint a name-specific `.git/info/exclude` line so the
        // renamed bundle doesn't leak into `git status`. A failure here does NOT
        // roll back the (already successful) move — a git-hygiene line doesn't
        // justify undoing a good rename; surface it via the log instead.
        let oldName = oldBundle.deletingPathExtension().lastPathComponent
        do {
            try GitExcludeRenamer().rename(
                oldBundleName: oldName, newBundleName: trimmed, repoURL: projectRoot)
        } catch {
            log.warning(
                "Bundle renamed to \(trimmed, privacy: .public).plumage but .git/info/exclude rewrite failed: \(error.localizedDescription, privacy: .public). The old exclude line may leave the renamed bundle showing in git status."
            )
        }

        return target
    }

    private static let log = Logger(subsystem: "com.plumage", category: "ProjectRenamer")
}
