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

        // Anchor for symlink containment check below. Resolved + standardized
        // once so the per-spec test is a plain prefix match.
        let projectRoot = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        let containmentBoundary = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"

        let discovered = issueFolders.compactMap { folder -> DiscoveredIssue? in
            let specURL = folder.appendingPathComponent("spec.md")
            guard fileManager.fileExists(atPath: specURL.path) else { return nil }
            // Reject any spec whose resolved path escapes the project root.
            // A hostile or careless repo could plant a symlink at
            // .claude/issues/00001-pwn/spec.md → /etc/passwd or
            // ~/.ssh/id_rsa; without this guard Plumage would happily read
            // and display its contents, and a subsequent save through
            // SpecWriter would overwrite the target.
            let resolvedPath = specURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolvedPath.hasPrefix(containmentBoundary) else {
                logger.error(
                    "Skipping spec outside project root: \(resolvedPath, privacy: .public)")
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
                var stamped = issue
                stamped.evidenceStamp = evidenceStamp(for: folder)
                return .valid(stamped)
            case .failure(let err):
                return .invalid(folder: folder, error: err)
            }
        }

        return discovered.sortedForKanban()
    }

    private static func evidenceStamp(for folder: URL) -> String? {
        let url = folder.appendingPathComponent("evidence.json")
        guard
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey,
            ]),
            let modified = values.contentModificationDate
        else { return nil }
        return "\(values.fileSize ?? 0)-\(modified.timeIntervalSince1970)"
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
