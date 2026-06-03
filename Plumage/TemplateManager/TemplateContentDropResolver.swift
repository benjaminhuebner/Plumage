import Foundation

// Resolves where an internal move-drop in the Template Manager content tree writes
// to. Mirrors the Navigator's `FileTreeDropResolver`, but the content tree's nodes
// carry a dual path (folder nodes hold their output path, file leaves hold their
// override-store path), so the target store directory is derived per node kind. Pure
// and `nonisolated` so the move semantics can be unit-tested without disk.
nonisolated enum TemplateContentDropResolver {
    // Override-store namespaces that back the tree's internals rather than a movable
    // user surface — dropping onto them (or onto a file living in them) is rejected.
    static let nonTargetStoreRoots: Set<String> = ["configs", "templates", "template-images"]

    // The override-store path of a node: a folder's output path mapped back to the
    // store, a file leaf's already-stored relative path.
    static func storePath(for node: FileNode) -> String {
        node.isDirectory
            ? TemplateManagerModel.storageDir(forOutputFolder: node.relativePath)
            : node.relativePath
    }

    // The override-store directory a drop onto `node` writes into: a folder row targets
    // itself, a file row targets its containing folder. Returns nil for nodes outside
    // the movable managed surfaces (the store's internal namespaces).
    static func targetStoreDir(for node: FileNode) -> String? {
        let store = storePath(for: node)
        let dir = node.isDirectory ? store : (store as NSString).deletingLastPathComponent
        let head = dir.split(separator: "/").first.map(String.init) ?? dir
        if nonTargetStoreRoots.contains(head) { return nil }
        return dir
    }

    // True when moving the store item at `source` into `targetStoreDir` would drop a
    // folder into itself or its own subtree, or is a no-op into its current folder.
    static func rejectsMove(storePath source: String, intoStoreDir target: String) -> Bool {
        if target == source || target.hasPrefix(source + "/") { return true }  // self / subtree
        return (source as NSString).deletingLastPathComponent == target  // already there
    }
}
