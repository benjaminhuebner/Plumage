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
    static let settingsRootRelativePath = ".claude"

    // Mirrors IssueArchiver.maxArchiveSuffix — same rationale (deterministic
    // failure on adversarial FS state, unreachable under normal use).
    static let maxNameSuffix = 1000

    static func enumerateDocs(projectURL: URL) throws -> [URL] {
        let dir = projectURL.appendingPathComponent(docsRelativePath, isDirectory: true)
        return try listFiles(in: dir, withExtension: "md")
    }

    static func enumerateHooks(projectURL: URL) throws -> [URL] {
        let dir = projectURL.appendingPathComponent(hooksRelativePath, isDirectory: true)
        return try listFiles(in: dir, withExtension: "sh")
    }

    static func enumerateSkills(projectURL: URL) throws -> [SkillNode] {
        let dir = projectURL.appendingPathComponent(skillsRelativePath, isDirectory: true)
        return try buildTree(at: dir)
    }

    // Free *.md files at .claude/ root, excluding CLAUDE.md (which has its own
    // route). Used by the new "Claude → CLAUDE-Markdown-Liste" sidebar entries.
    static func enumerateClaudeMarkdown(projectURL: URL) throws -> [URL] {
        let dir = projectURL.appendingPathComponent(settingsRootRelativePath, isDirectory: true)
        let all = try listFiles(in: dir, withExtension: "md")
        return all.filter { $0.lastPathComponent != "CLAUDE.md" }
    }

    static func claudeMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeMDRelativePath)
    }

    static func settingsURL(projectURL: URL, file: SettingsFile) -> URL {
        projectURL
            .appendingPathComponent(settingsRootRelativePath, isDirectory: true)
            .appendingPathComponent(file.rawValue)
    }

    // MARK: - Creators

    static func createDoc(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(docsRelativePath, isDirectory: true)
        let normalized = normalizedFileName(name, allowedExtensions: ["md"], fallback: "md")
        return try createFile(in: dir, baseName: normalized, defaultContent: "")
    }

    static func createClaudeMarkdown(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(settingsRootRelativePath, isDirectory: true)
        let normalized = normalizedFileName(name, allowedExtensions: ["md"], fallback: "md")
        // Reject the CLAUDE.md reserved name — it has its own bootstrap route.
        guard normalized != "CLAUDE.md" else {
            throw ClaudeProjectFilesError.reservedName(normalized)
        }
        return try createFile(in: dir, baseName: normalized, defaultContent: "")
    }

    static func createHookFile(name: String, projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent(hooksRelativePath, isDirectory: true)
        let normalized = normalizedFileName(name, allowedExtensions: ["sh", "py"], fallback: "sh")
        let content = hookShebang(forExtension: (normalized as NSString).pathExtension)
        return try createFile(in: dir, baseName: normalized, defaultContent: content)
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

    private static func hookShebang(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "py": return "#!/usr/bin/env python3\n"
        case "sh": return "#!/usr/bin/env bash\nset -euo pipefail\n"
        default: return "#!/usr/bin/env bash\nset -euo pipefail\n"
        }
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
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return
            entries
            .filter { $0.pathExtension == ext }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
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
