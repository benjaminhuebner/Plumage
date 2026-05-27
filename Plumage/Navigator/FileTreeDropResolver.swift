import Foundation

// Pure URL-resolution for the file tree's `.dropDestination` modifier.
// Splits the view-level question ("user dropped on this row") from the
// model-level question ("which folder receives the copy"). Folder rows
// land drops into themselves; file rows redirect to their parent
// (Finder-consistent). Returns `nil` when the resolved target sits
// outside the whitelisted tree, signalling a reject.
nonisolated enum FileTreeDropResolver {
    static func resolveDropTarget(
        for node: FileNode, projectURL: URL
    ) -> URL? {
        let target = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        guard isInsideWhitelistedTree(target, projectURL: projectURL) else {
            return nil
        }
        return target
    }

    static func isInsideWhitelistedTree(_ url: URL, projectURL: URL) -> Bool {
        let claude =
            projectURL
            .appendingPathComponent(FileTreeBuilder.claudeRoot, isDirectory: true)
            .standardizedFileURL.path
        let plumage =
            projectURL
            .appendingPathComponent(FileTreeBuilder.plumageRoot, isDirectory: true)
            .standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target == claude || target.hasPrefix(claude + "/")
            || target == plumage || target.hasPrefix(plumage + "/")
    }
}
