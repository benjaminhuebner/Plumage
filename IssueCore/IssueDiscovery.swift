import Foundation

nonisolated enum IssueDiscovery {
    static func discoverIssues(in projectURL: URL) -> [Issue] {
        let issuesDir = projectURL.appendingPathComponent(".claude/issues", isDirectory: true)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: issuesDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
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

        let parsed = issueFolders.compactMap { folder -> (folderName: String, issue: Issue)? in
            let specURL = folder.appendingPathComponent("spec.md")
            guard let content = try? String(contentsOf: specURL, encoding: .utf8) else { return nil }
            guard let issue = SpecParser.parse(content: content) else { return nil }
            return (folder.lastPathComponent, issue)
        }

        return
            parsed
            .sorted { lhs, rhs in
                if lhs.issue.id != rhs.issue.id { return lhs.issue.id < rhs.issue.id }
                return lhs.folderName < rhs.folderName
            }
            .map(\.issue)
    }
}
