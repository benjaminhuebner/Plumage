import Foundation

nonisolated enum FileTreeBuilder {
    static let claudeRoot = ".claude"
    static let plumageRoot = ".plumage"
    static let rootFileWhitelist: [String] = [".mcp.json", "CLAUDE.md", "CLAUDE.local.md"]

    static func build(projectURL: URL) -> [FileNode] {
        var nodes: [FileNode] = []

        for folder in [claudeRoot, plumageRoot] {
            let url = projectURL.appendingPathComponent(folder, isDirectory: true)
            if let node = makeNode(at: url, projectURL: projectURL) {
                nodes.append(node)
            }
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
                    children: nil
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
                children: nil
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
}
