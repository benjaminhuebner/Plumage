import Foundation

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
        let target = url.standardizedFileURL.path
        return target == claude || target.hasPrefix(claude + "/")
    }
}
