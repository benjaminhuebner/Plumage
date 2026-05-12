import Foundation

nonisolated enum IssueDiscovery {
    static func discoverIssues(in projectURL: URL) -> [Issue] {
        let issuesDir = projectURL.appendingPathComponent(".claude/issues", isDirectory: true)
        let fileManager = FileManager.default
        let rootIsDir = (try? issuesDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard rootIsDir else { return [] }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: issuesDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        let issueFolders =
            entries
            .filter { url in
                url.lastPathComponent != "archive"
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

        let parsed = issueFolders.compactMap { folder -> Issue? in
            let specURL = folder.appendingPathComponent("spec.md")
            guard let content = try? String(contentsOf: specURL, encoding: .utf8) else { return nil }
            return SpecParser.parse(content: content, folder: folder.lastPathComponent)
        }

        return parsed.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            return lhs.folder < rhs.folder
        }
    }
}
