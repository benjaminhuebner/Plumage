import AppKit
import SwiftUI

// NSOutlineView tracks items by object identity — value-type nodes would
// collapse expansion and selection on every rebuild.
final class FinderFileTreeItem {
    var node: FileNode
    var children: [FinderFileTreeItem]

    init(node: FileNode) {
        self.node = node
        self.children = (node.children ?? []).map(FinderFileTreeItem.init)
    }
}

final class FinderFileTreeCoordinator: NSObject {
    weak var outlineView: NSOutlineView?
    var onSelect: ((FileNode?) -> Void)?
    var onExpansionChange: ((Set<String>) -> Void)?
    var rowContent: ((FileNode) -> AnyView)?

    private(set) var rootItems: [FinderFileTreeItem] = []
    private var itemsByPath: [String: FinderFileTreeItem] = [:]
    private var currentNodes: [FileNode] = []
    private(set) var expandedPaths: Set<String> = []
    // Suppresses the expansion-change callback while expansion is being
    // *applied* from SwiftUI state — only user-initiated toggles report back.
    private var isApplyingExpansion = false
    private var lastRevealID: UUID?

    func item(forPath path: String) -> FinderFileTreeItem? {
        itemsByPath[path]
    }

    // MARK: - Nodes

    func setNodes(_ newNodes: [FileNode]) {
        guard newNodes != currentNodes else { return }
        let oldNodes = currentNodes
        currentNodes = newNodes
        guard let outlineView, !oldNodes.isEmpty, !rootItems.isEmpty else {
            rebuildAll()
            outlineView?.reloadData()
            applyExpansionState()
            return
        }
        let diffs = FileTreeDiff.diff(old: oldNodes, new: newNodes)
        guard !diffs.isEmpty else {
            syncNodePayloads()
            return
        }
        syncNodePayloads()
        outlineView.beginUpdates()
        for diff in diffs { apply(diff, to: outlineView) }
        outlineView.endUpdates()
        applyExpansionState()
    }

    private func rebuildAll() {
        rootItems = currentNodes.map(FinderFileTreeItem.init)
        itemsByPath = [:]
        rootItems.forEach(register)
    }

    private func register(_ item: FinderFileTreeItem) {
        itemsByPath[item.node.relativePath] = item
        item.children.forEach(register)
    }

    private func unregister(_ item: FinderFileTreeItem) {
        itemsByPath.removeValue(forKey: item.node.relativePath)
        item.children.forEach(unregister)
    }

    // Kept items hold the *old* node value after a reload; their shallow
    // fields drive rows, but `children` and `url` must not go stale for
    // later callbacks (drop targets, context menus).
    private func syncNodePayloads() {
        func sync(_ nodes: [FileNode]) {
            for node in nodes {
                if let item = itemsByPath[node.relativePath] { item.node = node }
                if let children = node.children { sync(children) }
            }
        }
        sync(currentNodes)
    }

    private func apply(_ diff: FileTreeChildDiff, to outlineView: NSOutlineView) {
        let parentItem = diff.parentPath.flatMap { itemsByPath[$0] }
        let newChildNodes = childNodes(forParentPath: diff.parentPath)

        if diff.needsReorder {
            reorderChildren(of: parentItem, to: newChildNodes, in: outlineView)
        } else {
            var children = parentItem?.children ?? rootItems
            for index in diff.removedIndices.sorted(by: >) {
                unregister(children.remove(at: index))
            }
            if !diff.removedIndices.isEmpty {
                outlineView.removeItems(
                    at: IndexSet(diff.removedIndices), inParent: parentItem,
                    withAnimation: .effectFade)
            }
            for index in diff.insertedIndices.sorted() {
                let item = FinderFileTreeItem(node: newChildNodes[index])
                register(item)
                children.insert(item, at: index)
            }
            setChildren(children, of: parentItem)
            if !diff.insertedIndices.isEmpty {
                outlineView.insertItems(
                    at: IndexSet(diff.insertedIndices), inParent: parentItem,
                    withAnimation: .effectFade)
            }
        }

        for path in diff.updatedPaths {
            guard let item = itemsByPath[path] else { continue }
            outlineView.reloadItem(item, reloadChildren: false)
        }
    }

    private func reorderChildren(
        of parentItem: FinderFileTreeItem?, to newChildNodes: [FileNode],
        in outlineView: NSOutlineView
    ) {
        let existing = parentItem?.children ?? rootItems
        var byPath: [String: FinderFileTreeItem] = [:]
        for child in existing { byPath[child.node.relativePath] = child }
        var rebuilt: [FinderFileTreeItem] = []
        for node in newChildNodes {
            if let kept = byPath.removeValue(forKey: node.relativePath) {
                rebuilt.append(kept)
            } else {
                let item = FinderFileTreeItem(node: node)
                register(item)
                rebuilt.append(item)
            }
        }
        byPath.values.forEach(unregister)
        setChildren(rebuilt, of: parentItem)
        if let parentItem {
            outlineView.reloadItem(parentItem, reloadChildren: true)
        } else {
            outlineView.reloadData()
        }
    }

    private func setChildren(_ children: [FinderFileTreeItem], of parent: FinderFileTreeItem?) {
        if let parent {
            parent.children = children
        } else {
            rootItems = children
        }
    }

    private func childNodes(forParentPath parentPath: String?) -> [FileNode] {
        guard let parentPath else { return currentNodes }
        func find(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.relativePath == parentPath { return node }
                if parentPath.hasPrefix(node.relativePath + "/"), let children = node.children,
                    let found = find(children)
                {
                    return found
                }
            }
            return nil
        }
        return find(currentNodes)?.children ?? []
    }

    // MARK: - Expansion

    func setExpandedPaths(_ paths: Set<String>) {
        guard paths != expandedPaths else { return }
        expandedPaths = paths
        applyExpansionState(collapsingOthers: true)
    }

    private func applyExpansionState(collapsingOthers: Bool = false) {
        guard let outlineView else { return }
        isApplyingExpansion = true
        defer { isApplyingExpansion = false }
        // Ancestors first, so a deep path expands its whole chain.
        let ordered = expandedPaths.sorted {
            $0.split(separator: "/").count < $1.split(separator: "/").count
        }
        for path in ordered {
            guard let item = itemsByPath[path], item.node.isDirectory else { continue }
            if !outlineView.isItemExpanded(item) { outlineView.expandItem(item) }
        }
        guard collapsingOthers else { return }
        for (path, item) in itemsByPath
        where item.node.isDirectory && !expandedPaths.contains(path) {
            if outlineView.isItemExpanded(item) { outlineView.collapseItem(item) }
        }
    }

    // MARK: - Reveal

    func handleReveal(_ request: FileTreeRevealRequest) {
        guard request.id != lastRevealID else { return }
        lastRevealID = request.id
        reveal(path: request.path)
    }

    func reveal(path: String) {
        guard let outlineView, let item = itemsByPath[path] else { return }
        for ancestor in Self.ancestorPaths(of: path) {
            guard let ancestorItem = itemsByPath[ancestor],
                !outlineView.isItemExpanded(ancestorItem)
            else { continue }
            outlineView.expandItem(ancestorItem)
        }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    nonisolated static func ancestorPaths(of path: String) -> [String] {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }
        var result: [String] = []
        var prefix = ""
        for component in components.dropLast() {
            prefix = prefix.isEmpty ? component : prefix + "/" + component
            result.append(prefix)
        }
        return result
    }
}

extension FinderFileTreeCoordinator: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? FinderFileTreeItem else { return rootItems.count }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? FinderFileTreeItem else { return rootItems[index] }
        return item.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FinderFileTreeItem)?.node.isDirectory ?? false
    }
}

extension FinderFileTreeCoordinator: NSOutlineViewDelegate {
    func outlineView(
        _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
    ) -> NSView? {
        guard let item = item as? FinderFileTreeItem, let rowContent else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FinderFileTreeCell")
        let cell =
            outlineView.makeView(withIdentifier: identifier, owner: nil)
            as? FinderFileTreeCellView ?? FinderFileTreeCellView(identifier: identifier)
        cell.show(rowContent(item.node))
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let row = outlineView.selectedRow
        let node = row >= 0 ? (outlineView.item(atRow: row) as? FinderFileTreeItem)?.node : nil
        onSelect?(node)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isApplyingExpansion,
            let item = notification.userInfo?["NSObject"] as? FinderFileTreeItem
        else { return }
        expandedPaths.insert(item.node.relativePath)
        onExpansionChange?(expandedPaths)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isApplyingExpansion,
            let item = notification.userInfo?["NSObject"] as? FinderFileTreeItem
        else { return }
        expandedPaths.remove(item.node.relativePath)
        onExpansionChange?(expandedPaths)
    }
}

// One hosting view per cell, reused via `rootView` swap — rebuilding the
// SwiftUI hierarchy on every reuse causes scroll jank.
final class FinderFileTreeCellView: NSTableCellView {
    private let hosting: NSHostingView<AnyView>

    init(identifier: NSUserInterfaceItemIdentifier) {
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        self.identifier = identifier
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ view: AnyView) {
        hosting.rootView = view
    }
}
