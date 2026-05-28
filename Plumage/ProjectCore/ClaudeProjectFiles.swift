import Foundation

nonisolated enum ClaudeProjectFiles {
    static let claudeRelativePath = ".claude"
    static let claudeMDRelativePath = ".claude/CLAUDE.md"
    static let claudeLocalMDRelativePath = ".claude/CLAUDE.local.md"
    static let settingsRootRelativePath = ".claude"
    static let skillsRelativePath = ".claude/skills"
    static let mcpJSONRelativePath = ".mcp.json"

    // Mirrors IssueArchiver.maxArchiveSuffix — same rationale (deterministic
    // failure on adversarial FS state, unreachable under normal use).
    static let maxNameSuffix = 1000

    // MARK: - Known root file URLs

    static func claudeMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeMDRelativePath)
    }

    static func claudeLocalMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeLocalMDRelativePath)
    }

    static func mcpJSONURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(mcpJSONRelativePath)
    }

    // MARK: - Generic at-path create (used by the unified file tree)

    // Creates an empty file under `parent`, suffix-walking on collision.
    static func createFileAt(parent: URL, name: String) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = try findFreeName(in: parent, base: trimmed)
        // `trimmed` may carry path separators ("team/lead.md"); create the
        // intervening folders so the leaf write doesn't fail on a missing dir.
        try fm.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target)
        return target
    }

    // Creates a folder under `parent`, suffix-walking on collision.
    static func createFolderAt(parent: URL, name: String) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = try findFreeName(in: parent, base: trimmed)
        // `withIntermediateDirectories: true` so a separator-bearing name
        // ("team/reviewers") creates the whole chain; `findFreeName` already
        // guarantees `target` itself is free.
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    // MARK: - Rename / Move / Trash

    // Renames a file or folder in place. Preserves the original file's
    // extension if the user typed a stem-only name; folders rename as typed.
    // Suffix-walks on collision so renaming "foo.md" over an existing
    // "foo.md" lands at "foo-1.md".
    static func renameFile(at url: URL, to newName: String) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let normalized: String
        if isDir {
            normalized = trimmed
        } else {
            let typedExt = (trimmed as NSString).pathExtension
            let originalExt = url.pathExtension
            if typedExt.isEmpty && !originalExt.isEmpty {
                normalized = "\(trimmed).\(originalExt)"
            } else {
                normalized = trimmed
            }
        }
        if normalized == url.lastPathComponent {
            return url
        }
        let target = try findFreeName(in: parent, base: normalized)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    // Moves a file or folder into a new parent directory. Rejects moves where
    // `source` is an ancestor of `targetFolder`. Suffix-walks on collision.
    static func moveItem(at source: URL, to targetFolder: URL) throws -> URL {
        let fm = FileManager.default
        let sourcePath = source.standardizedFileURL.path
        let targetPath = targetFolder.standardizedFileURL.path
        // No-op: item dropped back into the folder it already lives in.
        // Return it unchanged — no suffix-walk, no rename. (Must come before
        // findFreeName, which would otherwise collide with the source itself
        // and walk to `name-1`.)
        if source.deletingLastPathComponent().standardizedFileURL.path == targetPath {
            return source
        }
        try fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        if targetPath == sourcePath || targetPath.hasPrefix(sourcePath + "/") {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let target = try findFreeName(
            in: targetFolder, base: source.lastPathComponent)
        try fm.moveItem(at: source, to: target)
        return target
    }

    static func trashFile(at url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let resulting = resulting as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return resulting
    }

    // MARK: - Free-name helper

    // Returns the first URL whose lastPathComponent (with the same extension
    // for files, or as-is for folders) isn't taken in `directory`. Mirrors
    // IssueArchiver's suffix strategy: `<base>`, `<base>-1`, `<base>-2`, …
    static func findFreeName(in directory: URL, base: String) throws -> URL {
        let fileManager = FileManager.default
        let nameNS = base as NSString
        let ext = nameNS.pathExtension
        let stem = nameNS.deletingPathExtension

        let first = directory.appendingPathComponent(base)
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }
        for suffix in 1...maxNameSuffix {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(stem)-\(suffix)"
            } else {
                candidateName = "\(stem)-\(suffix).\(ext)"
            }
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

nonisolated enum ClaudeProjectFilesError: Error, Equatable, Sendable {
    case reservedName(String)
}
