import Foundation

nonisolated struct FileTreeChildDiff: Equatable, Sendable {
    let parentPath: String?
    let removedIndices: [Int]
    let insertedIndices: [Int]
    let updatedPaths: [String]
    let needsReorder: Bool
}

nonisolated enum FileTreeDiff {
    static func diff(old: [FileNode], new: [FileNode]) -> [FileTreeChildDiff] {
        var result: [FileTreeChildDiff] = []
        walk(parentPath: nil, old: old, new: new, into: &result)
        return result
    }

    // Compares everything except `children` — structural child changes are
    // their own diff entries, so a parent must not count as "updated" merely
    // because a grandchild moved.
    static func shallowEqual(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        lhs.url == rhs.url && lhs.name == rhs.name && lhs.isDirectory == rhs.isDirectory
            && lhs.isEmptyContextFile == rhs.isEmptyContextFile
    }

    private static func walk(
        parentPath: String?, old: [FileNode], new: [FileNode],
        into result: inout [FileTreeChildDiff]
    ) {
        let oldIDs = old.map(\.id)
        let newIDs = new.map(\.id)
        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        let removed = old.indices.filter { !newSet.contains(old[$0].id) }
        let inserted = new.indices.filter { !oldSet.contains(new[$0].id) }
        let keptOld = oldIDs.filter(newSet.contains)
        let keptNew = newIDs.filter(oldSet.contains)
        let needsReorder = keptOld != keptNew

        var oldByID: [String: FileNode] = [:]
        for node in old { oldByID[node.id] = node }
        var updated: [String] = []
        for node in new {
            guard let prior = oldByID[node.id] else { continue }
            if !shallowEqual(prior, node) { updated.append(node.id) }
        }

        if !removed.isEmpty || !inserted.isEmpty || !updated.isEmpty || needsReorder {
            result.append(
                FileTreeChildDiff(
                    parentPath: parentPath,
                    removedIndices: removed,
                    insertedIndices: inserted,
                    updatedPaths: updated,
                    needsReorder: needsReorder))
        }

        for node in new where node.isDirectory {
            guard let prior = oldByID[node.id] else { continue }
            walk(
                parentPath: node.id, old: prior.children ?? [], new: node.children ?? [],
                into: &result)
        }
    }
}
