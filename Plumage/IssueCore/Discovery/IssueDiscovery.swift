import Foundation
import os

nonisolated enum IssueDiscovery {
    private static let logger = Logger(subsystem: "com.plumage", category: "IssueDiscovery")

    static func discoverIssues(in projectURL: URL) -> [DiscoveredIssue] {
        let issuesDir = IssueLayout.issuesDirectory(in: projectURL)
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
            logger.error(
                "Failed to list \(issuesDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        let issueFolders =
            entries
            .filter { url in
                url.lastPathComponent != "archive"
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

        let discovered = issueFolders.compactMap { folder -> DiscoveredIssue? in
            let specURL = folder.appendingPathComponent("spec.md")
            guard fileManager.fileExists(atPath: specURL.path) else { return nil }
            let content: String
            do {
                content = try String(contentsOf: specURL, encoding: .utf8)
            } catch {
                return .invalid(folder: folder, error: .unreadable(message: error.localizedDescription))
            }
            switch SpecParser.parse(content: content, folderName: folder.lastPathComponent) {
            case .success(let issue):
                return .valid(issue)
            case .failure(let err):
                return .invalid(folder: folder, error: err)
            }
        }

        return discovered.sortedForKanban()
    }

    static func extractID(fromFolderName folderName: String) -> (id: Int?, slug: String) {
        guard let dashIndex = folderName.firstIndex(of: "-") else {
            return (nil, folderName)
        }
        let prefix = folderName[..<dashIndex]
        let rest = folderName[folderName.index(after: dashIndex)...]
        if let id = Int(prefix) {
            return (id, String(rest))
        }
        return (nil, folderName)
    }
}
