import Foundation

nonisolated enum FileTreeBuilder {
    static let claudeRoot = ".claude"
    static let rootFileWhitelist: [String] = [".mcp.json", "CLAUDE.md", "CLAUDE.local.md"]

    static func build(projectURL: URL) -> [FileNode] {
        var nodes: [FileNode] = []

        // `.plumage/` is intentionally NOT shown — it holds Plumage's own
        // machinery (config.json, runs/), not user-editable workflow config.
        let claudeURL = projectURL.appendingPathComponent(claudeRoot, isDirectory: true)
        if let node = makeNode(at: claudeURL, projectURL: projectURL) {
            nodes.append(node)
        }

        let fm = FileManager.default
        for fileName in rootFileWhitelist {
            let url = projectURL.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: url.path) else { continue }
            if isSymlink(url) { continue }
            nodes.append(
                FileNode(
                    url: url,
                    relativePath: fileName,
                    name: fileName,
                    isDirectory: false,
                    children: nil,
                    isEmptyContextFile: emptyContextFlag(relativePath: fileName, url: url)
                )
            )
        }

        return nodes
    }

    private static func makeNode(at url: URL, projectURL: URL) -> FileNode? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if isSymlink(url) { return nil }
        let name = url.lastPathComponent
        if shouldSkip(name) { return nil }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let relativePath = relativize(url: url, projectURL: projectURL)

        if !isDir {
            return FileNode(
                url: url,
                relativePath: relativePath,
                name: name,
                isDirectory: false,
                children: nil,
                isEmptyContextFile: emptyContextFlag(relativePath: relativePath, url: url)
            )
        }

        let entries =
            (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )) ?? []

        var folders: [FileNode] = []
        var files: [FileNode] = []
        for entry in entries {
            guard let child = makeNode(at: entry, projectURL: projectURL) else { continue }
            if child.isDirectory {
                folders.append(child)
            } else {
                files.append(child)
            }
        }
        folders.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        files.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return FileNode(
            url: url,
            relativePath: relativePath,
            name: name,
            isDirectory: true,
            children: folders + files
        )
    }

    // Reads file content ONLY for the ≤3 foundation context paths so I/O stays
    // bounded; every other node skips the read. A read failure fails safe to
    // `false` so a permission error never shows a scary false warning.
    private static func emptyContextFlag(relativePath: String, url: URL) -> Bool {
        guard EmptyContextFiles.isTarget(relativePath: relativePath) else { return false }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return EmptyContextFiles.isEffectivelyEmpty(content)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    private static func shouldSkip(_ name: String) -> Bool {
        name == ".DS_Store" || name == "Icon\r"
    }

    private static func relativize(url: URL, projectURL: URL) -> String {
        let projPath = projectURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(projPath + "/") {
            return String(urlPath.dropFirst(projPath.count + 1))
        }
        return url.lastPathComponent
    }

    // Flat snapshot of every file (not folder) in a built tree: the set of
    // relative paths (authoritative existence) plus a path→inode map. The
    // inode is stable across a same-volume rename/move, so diffing two indexes
    // distinguishes "file moved to a new path" from "file vanished" — the basis
    // for following external renames of pinned files.
    nonisolated struct FileIndex: Sendable {
        let paths: Set<String>
        let inodes: [String: Int]
    }

    static func fileIndex(in nodes: [FileNode]) -> FileIndex {
        var paths: Set<String> = []
        var inodes: [String: Int] = [:]
        func walk(_ node: FileNode) {
            if node.isDirectory {
                node.children?.forEach(walk)
            } else {
                paths.insert(node.relativePath)
                if let ino = inode(of: node.url) {
                    inodes[node.relativePath] = ino
                }
            }
        }
        nodes.forEach(walk)
        return FileIndex(paths: paths, inodes: inodes)
    }

    private static func inode(of url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.systemFileNumber] as? Int
    }
}
