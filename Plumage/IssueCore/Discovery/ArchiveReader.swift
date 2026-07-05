import Foundation
import os

nonisolated enum ArchiveReader {
    private static let logger = Logger(subsystem: "com.plumage", category: "ArchiveReader")

    static func discoverArchivedIssues(inArchive archiveDirectory: URL) -> [DiscoveredIssue] {
        let fileManager = FileManager.default
        let rootIsDir =
            (try? archiveDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard rootIsDir else { return [] }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: archiveDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error(
                "Failed to list \(archiveDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        let issueFolders = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        let archiveRoot = archiveDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let containmentBoundary = archiveRoot.hasSuffix("/") ? archiveRoot : archiveRoot + "/"

        let discovered = issueFolders.compactMap { folder -> DiscoveredIssue? in
            let specURL = folder.appendingPathComponent("spec.md")
            guard fileManager.fileExists(atPath: specURL.path) else { return nil }
            let resolvedPath = specURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedPath.hasPrefix(containmentBoundary) else {
                logger.error(
                    "Skipping archived spec outside archive root: \(resolvedPath, privacy: .public)")
                return nil
            }
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

    static func archivedGitHubNumbers(inArchive archiveDirectory: URL) -> Set<Int> {
        var numbers = Set<Int>()
        for case .valid(let issue) in discoverArchivedIssues(inArchive: archiveDirectory) {
            if let github = issue.github { numbers.insert(github) }
        }
        return numbers
    }
}
