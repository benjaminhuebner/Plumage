import Foundation

nonisolated enum SkillNode: Hashable, Sendable {
    case file(URL)
    case folder(name: String, children: [SkillNode])
}

nonisolated enum ClaudeProjectFiles {
    static let docsRelativePath = ".claude/docs"
    static let hooksRelativePath = ".claude/hooks"
    static let skillsRelativePath = ".claude/skills"
    static let claudeMDRelativePath = ".claude/CLAUDE.md"
    static let claudeLocalMDRelativePath = ".claude/CLAUDE.local.md"
    static let settingsRootRelativePath = ".claude"
    static let mcpJSONRelativePath = ".mcp.json"

    // Mirrors IssueArchiver.maxArchiveSuffix — same rationale (deterministic
    // failure on adversarial FS state, unreachable under normal use).
    static let maxNameSuffix = 1000

    // MARK: - Generic enumerate / create

    static func enumerate(_ type: ManagedFileType, projectURL: URL) throws -> [URL] {
        let dir = projectURL.appendingPathComponent(type.relativePath, isDirectory: true)
        if type.recursive {
            return try listFilesRecursive(in: dir, withExtensions: type.allowedExtensions)
        }
        return try listFiles(in: dir, withExtensions: type.allowedExtensions)
    }

    static func create(_ type: ManagedFileType, name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(type.relativePath, isDirectory: true)
        // Recursive sections (agents, rules) take user-typed paths as nested
        // subpaths — `team/lead.md` lands at `.claude/agents/team/lead.md` and
        // createFile creates the intermediate dir. Non-recursive sections
        // collapse separators to `-` so a stray `/` can't escape the section.
        let prepared = type.recursive ? name : flattenPathSeparators(name)
        let normalized = normalizedFileName(
            prepared,
            allowedExtensions: Array(type.allowedExtensions),
            fallback: type.defaultExtension)
        // defaultStub keys off the leaf for the frontmatter `name:` field.
        let content = type.defaultStub(filename: (normalized as NSString).lastPathComponent)
        return try createFile(in: dir, baseName: normalized, defaultContent: content)
    }

    private static func flattenPathSeparators(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Type-specific wrappers (preserved for existing call-sites)

    static func enumerateDocs(projectURL: URL) throws -> [URL] {
        try enumerate(.docs, projectURL: projectURL)
    }

    static func enumerateHooks(projectURL: URL) throws -> [URL] {
        try enumerate(.hooks, projectURL: projectURL)
    }

    static func enumerateSkills(projectURL: URL) throws -> [SkillNode] {
        let dir = projectURL.appendingPathComponent(skillsRelativePath, isDirectory: true)
        return try buildTree(at: dir)
    }

    // Free *.md files at .claude/ root, excluding CLAUDE.md and CLAUDE.local.md
    // (both have their own routes). Used by the "Claude" sidebar section.
    static func enumerateClaudeMarkdown(projectURL: URL) throws -> [URL] {
        let dir = projectURL.appendingPathComponent(settingsRootRelativePath, isDirectory: true)
        let all = try listFiles(in: dir, withExtensions: ["md"])
        return all.filter {
            $0.lastPathComponent != "CLAUDE.md" && $0.lastPathComponent != "CLAUDE.local.md"
        }
    }

    static func claudeMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeMDRelativePath)
    }

    static func claudeLocalMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeLocalMDRelativePath)
    }

    static func mcpJSONURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(mcpJSONRelativePath)
    }

    static func settingsURL(projectURL: URL, file: SettingsFile) -> URL {
        projectURL
            .appendingPathComponent(settingsRootRelativePath, isDirectory: true)
            .appendingPathComponent(file.rawValue)
    }

    // MARK: - Creators

    static func createDoc(name: String, projectURL: URL) throws -> URL {
        try create(.docs, name: name, projectURL: projectURL)
    }

    static func createClaudeMarkdown(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(settingsRootRelativePath, isDirectory: true)
        let normalized = normalizedFileName(name, allowedExtensions: ["md"], fallback: "md")
        // Reject the CLAUDE.md and CLAUDE.local.md reserved names — both have
        // dedicated bootstrap routes in the sidebar.
        guard normalized != "CLAUDE.md", normalized != "CLAUDE.local.md" else {
            throw ClaudeProjectFilesError.reservedName(normalized)
        }
        return try createFile(in: dir, baseName: normalized, defaultContent: "")
    }

    static func createHookFile(name: String, projectURL: URL) throws -> URL {
        try create(.hooks, name: name, projectURL: projectURL)
    }

    static func createHookFolder(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(hooksRelativePath, isDirectory: true)
        return try createFolder(in: dir, baseName: sanitizeFolderName(name))
    }

    static func createSkill(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(skillsRelativePath, isDirectory: true)
        let folderURL = try createFolder(in: dir, baseName: sanitizeFolderName(name))
        let skillStub = skillMDStub(skillName: folderURL.lastPathComponent)
        let skillMD = folderURL.appendingPathComponent("SKILL.md")
        try skillStub.write(to: skillMD, atomically: true, encoding: .utf8)
        return folderURL
    }

    static func createSkillFolder(
        name: String,
        underSkill skillName: String,
        relativePath: String,
        projectURL: URL
    ) throws -> URL {
        let parent = skillSubdirectory(
            projectURL: projectURL, skillName: skillName, relativePath: relativePath)
        return try createFolder(in: parent, baseName: sanitizeFolderName(name))
    }

    static func createSkillFile(
        name: String,
        underSkill skillName: String,
        relativePath: String,
        projectURL: URL
    ) throws -> URL {
        let parent = skillSubdirectory(
            projectURL: projectURL, skillName: skillName, relativePath: relativePath)
        let normalized = normalizedFileName(
            name, allowedExtensions: ["md", "sh", "py"], fallback: "md")
        let content = skillFileDefaultContent(forName: normalized)
        return try createFile(in: parent, baseName: normalized, defaultContent: content)
    }

    // MARK: - Rename / Trash

    // Renames a file or folder in place. The new name is normalized against
    // the same allowed-extension rules as the section's creator (so a Doc
    // renamed to "foo" still keeps the `.md` suffix). Suffix-walks on
    // collision so renaming "foo.md" over an existing "foo.md" lands at
    // "foo-1.md".
    static func renameFile(
        at url: URL,
        to newName: String,
        projectURL: URL
    ) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let normalized: String
        if isDir {
            normalized = sanitizeFolderName(newName)
        } else {
            let allowed = allowedExtensions(forParent: parent, projectURL: projectURL)
            let fallback = allowed.first ?? (url.pathExtension.isEmpty ? "md" : url.pathExtension)
            normalized = normalizedFileName(
                newName, allowedExtensions: Array(allowed), fallback: fallback)
        }
        // Same-name no-op: don't trigger a move + suffix-walk if the user
        // hit Enter without changing anything.
        if normalized == url.lastPathComponent {
            return url
        }
        let target = try findFreeName(in: parent, base: normalized)
        try FileManager.default.moveItem(at: url, to: target)
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

    // Returns the canonical extension whitelist for the directory a file
    // lives in. Used by renameFile so a Doc stays `.md` even when the user
    // types "foo" without an extension. Falls back to the original
    // extension if the parent isn't one of the known managed folders.
    private static func allowedExtensions(forParent parent: URL, projectURL: URL) -> Set<String> {
        let normalized = parent.standardizedFileURL.path
        let projectPath = projectURL.standardizedFileURL.path
        guard normalized.hasPrefix(projectPath) else { return [] }
        let relative = String(normalized.dropFirst(projectPath.count + 1))
        if relative == settingsRootRelativePath { return ["md"] }
        for type in ManagedFileType.allCases {
            let base = type.relativePath
            if relative == base { return type.allowedExtensions }
            // Recursive sections also accept the same extensions under
            // sub-folders so renaming preserves the suffix.
            if type.allowsSubfolders, relative.hasPrefix(base + "/") {
                return type.allowedExtensions
            }
        }
        if relative.hasPrefix(skillsRelativePath) { return ["md", "sh", "py"] }
        return []
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

    // MARK: - Private helpers

    private static func createFile(
        in directory: URL, baseName: String, defaultContent: String
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let target = try findFreeName(in: directory, base: baseName)
        // baseName may contain `/` for recursive sections (`team/lead.md`);
        // ensure the leaf's parent dir exists. Idempotent for flat names.
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try defaultContent.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    private static func createFolder(in directory: URL, baseName: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let target = try findFreeName(in: directory, base: baseName)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    private static func skillSubdirectory(
        projectURL: URL, skillName: String, relativePath: String
    ) -> URL {
        var url =
            projectURL
            .appendingPathComponent(skillsRelativePath, isDirectory: true)
            .appendingPathComponent(skillName, isDirectory: true)
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !trimmed.isEmpty {
            for component in trimmed.split(separator: "/") {
                url = url.appendingPathComponent(String(component), isDirectory: true)
            }
        }
        return url
    }

    // Forces the file's extension to one of `allowedExtensions`; if the input
    // already ends in one of them, it's kept as-is. Otherwise `.fallback` is
    // appended. Stem-only input gets the fallback. Trims surrounding
    // whitespace.
    static func normalizedFileName(
        _ raw: String, allowedExtensions: [String], fallback: String
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "untitled.\(fallback)" }
        let nameNS = trimmed as NSString
        let ext = nameNS.pathExtension.lowercased()
        let stem = nameNS.deletingPathExtension
        if !ext.isEmpty, allowedExtensions.contains(ext) {
            return "\(stem).\(ext)"
        }
        if ext.isEmpty {
            return "\(stem).\(fallback)"
        }
        // Treat the trailing dot-segment as part of the stem so we don't lose
        // a deliberate suffix the user typed (e.g. "PreToolUse.lint" → file
        // "PreToolUse.lint.sh").
        return "\(trimmed).\(fallback)"
    }

    private static func sanitizeFolderName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    private static func skillMDStub(skillName: String) -> String {
        """
        ---
        name: \(skillName)
        description: TODO describe what this skill does
        ---

        # \(skillName)
        """
    }

    private static func skillFileDefaultContent(forName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "sh": return "#!/usr/bin/env bash\nset -euo pipefail\n"
        case "py": return "#!/usr/bin/env python3\n"
        default: return ""
        }
    }

    private static func listFiles(in directory: URL, withExtension ext: String) throws -> [URL] {
        try listFiles(in: directory, withExtensions: [ext])
    }

    private static func listFiles(in directory: URL, withExtensions extensions: Set<String>) throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return
            entries
            .filter { extensions.contains($0.pathExtension) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // Walks the directory tree below `directory` and returns every regular file
    // whose pathExtension is in `extensions`. Hidden files (`.DS_Store`,
    // `._foo`) are skipped. Permission-denied subdirectories are swallowed by
    // `FileManager.enumerator` — they don't crash, they just don't contribute
    // entries (acceptable, matches the spec's "Permission denied" edge case).
    // Symbolic links (file and directory) are skipped and not traversed —
    // protects against symlink cycles under `.claude/agents` etc. that would
    // otherwise hang the enumerator.
    // Returned URLs are sorted by their project-relative path so list output
    // is stable across runs and across snapshots.
    private static func listFilesRecursive(
        in directory: URL, withExtensions extensions: Set<String>
    ) throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                // Skip the link itself and any descendants reachable through it.
                enumerator.skipDescendants()
                continue
            }
            let isRegular = values?.isRegularFile ?? false
            guard isRegular, extensions.contains(url.pathExtension) else { continue }
            results.append(url)
        }
        let basePath = directory.standardizedFileURL.path
        return results.sorted { lhs, rhs in
            relativeOrEmpty(lhs.standardizedFileURL.path, base: basePath)
                .localizedCaseInsensitiveCompare(
                    relativeOrEmpty(rhs.standardizedFileURL.path, base: basePath))
                == .orderedAscending
        }
    }

    private static func relativeOrEmpty(_ path: String, base: String) -> String {
        guard path.hasPrefix(base + "/") else { return path }
        return String(path.dropFirst(base.count + 1))
    }

    private static func buildTree(at directory: URL) throws -> [SkillNode] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var folders: [SkillNode] = []
        var files: [SkillNode] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = try buildTree(at: url)
                folders.append(.folder(name: url.lastPathComponent, children: children))
            } else {
                files.append(.file(url))
            }
        }

        folders.sort { folderName($0).localizedCaseInsensitiveCompare(folderName($1)) == .orderedAscending }
        files.sort { fileName($0).localizedCaseInsensitiveCompare(fileName($1)) == .orderedAscending }
        return folders + files
    }

    private static func folderName(_ node: SkillNode) -> String {
        if case .folder(let name, _) = node { return name }
        return ""
    }

    private static func fileName(_ node: SkillNode) -> String {
        if case .file(let url) = node { return url.lastPathComponent }
        return ""
    }
}

nonisolated enum ClaudeProjectFilesError: Error, Equatable, Sendable {
    case reservedName(String)
}
