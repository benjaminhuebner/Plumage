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

    static func claudeMDURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent(claudeMDRelativePath)
    }

    static func settingsURL(projectURL: URL, file: SettingsFile) -> URL {
        projectURL
            .appendingPathComponent(settingsRootRelativePath, isDirectory: true)
            .appendingPathComponent(file.rawValue)
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
