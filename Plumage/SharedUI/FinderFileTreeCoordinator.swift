import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    var onRenameRequest: ((FileNode) -> Void)?
    var onTrashRequest: (([FileNode]) -> Void)?
    var canDrag: ((FileNode) -> Bool)?
    var validateDrop: ((FileTreeDropPayload, FileNode?) -> Bool)?
    var onDrop: ((FileTreeDropPayload, FileNode?) -> Bool)?
    var contextMenu: (([FileNode]) -> NSMenu?)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var rowContent: ((FileNode) -> AnyView)?

    nonisolated static let internalDragType = NSPasteboard.PasteboardType(
        UTType.plumageFileTreeDrag.identifier)

    private(set) var rootItems: [FinderFileTreeItem] = []
    private var itemsByPath: [String: FinderFileTreeItem] = [:]
    private var currentNodes: [FileNode] = []
    // internal (not private): the delegate/data-source extensions live in
    // their own files since the split.
    var expandedPaths: Set<String> = []
    // Suppresses the expansion-change callback while expansion is being
    // *applied* from SwiftUI state — only user-initiated toggles report back.
    var isApplyingExpansion = false
    var isApplyingSelection = false
    private var lastRevealID: UUID?
    var lastSelectedPath: String?
    private weak var dropHighlightTarget: FinderFileTreeItem?
    private var frameObserver: NSObjectProtocol?
    private var lastReportedHeight: CGFloat = -1

    isolated deinit {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    // Frame observation alone misses shrinking: the outline is stretched to
    // fill its clip, so a collapse never changes the frame — the height must
    // come from the last row's rect, recomputed on every structural event.
    func observeContentHeight(of outline: NSOutlineView) {
        outline.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: outline, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reportContentHeight()
            }
        }
    }

    func reportContentHeight() {
        guard let outlineView, let onContentHeightChange else { return }
        let rows = outlineView.numberOfRows
        let height = rows > 0 ? outlineView.rect(ofRow: rows - 1).maxY : 0
        guard height != lastReportedHeight else { return }
        lastReportedHeight = height
        // Structural events can land mid layout pass — never write SwiftUI
        // state synchronously from here.
        Task { @MainActor in
            onContentHeightChange(height)
        }
    }

    func item(forPath path: String) -> FinderFileTreeItem? {
        itemsByPath[path]
    }

    // MARK: - Nodes

    func setNodes(_ newNodes: [FileNode]) {
        guard newNodes != currentNodes else { return }
        let oldNodes = currentNodes
        currentNodes = newNodes
        // Structural updates may drop the selected row; that must not report
        // as a user deselect — the bound selection is re-applied right after.
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        guard let outlineView, !oldNodes.isEmpty, !rootItems.isEmpty else {
            rebuildAll()
            outlineView?.reloadData()
            applyExpansionState()
            reportContentHeight()
            return
        }
        let diffs = FileTreeDiff.diff(old: oldNodes, new: newNodes)
        guard !diffs.isEmpty else {
            syncNodePayloads()
            return
        }
        syncNodePayloads()
        // Reorders go through reloadItem(reloadChildren:)/reloadData(), which
        // are not legal inside a begin/endUpdates batch — apply them after it.
        let structural = diffs.filter { !$0.needsReorder }
        if !structural.isEmpty {
            outlineView.beginUpdates()
            for diff in structural { apply(diff, to: outlineView) }
            outlineView.endUpdates()
        }
        for diff in diffs where diff.needsReorder { apply(diff, to: outlineView) }
        applyExpansionState()
        reportContentHeight()
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

    // No prefix shortcuts here: folder and file ids can live in different
    // path namespaces (Template Manager's output vs. store paths).
    private func childNodes(forParentPath parentPath: String?) -> [FileNode] {
        guard let parentPath else { return currentNodes }
        return itemsByPath[parentPath]?.node.children ?? []
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
        let ordered =
            expandedPaths
            .map { (path: $0, depth: $0.split(separator: "/").count) }
            .sorted { $0.depth < $1.depth }
            .map(\.path)
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

    // MARK: - Selection

    var selectedNodePath: String? {
        guard let outlineView, outlineView.selectedRow >= 0 else { return nil }
        return (outlineView.item(atRow: outlineView.selectedRow) as? FinderFileTreeItem)?
            .node.relativePath
    }

    func setSelectedPath(_ path: String?) {
        guard let outlineView, path != selectedNodePath else { return }
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        guard let path, let item = itemsByPath[path] else {
            outlineView.deselectAll(nil)
            return
        }
        let row = outlineView.row(forItem: item)
        // A row hidden under a collapsed ancestor stays unselected — flows
        // that must surface it (create, import) go through reveal instead.
        guard row >= 0 else { return }
        // A multi-selection that already contains the path stays untouched:
        // the single bound path is the lead row, not the whole selection.
        guard !outlineView.selectedRowIndexes.contains(row) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    // MARK: - Context menu

    func menu(for event: NSEvent) -> NSMenu? {
        guard let outlineView, let contextMenu else { return nil }
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0,
            let item = outlineView.item(atRow: row) as? FinderFileTreeItem
        else { return nil }
        let nodes: [FileNode]
        if outlineView.selectedRowIndexes.contains(row) {
            nodes = outlineView.selectedRowIndexes.compactMap {
                (outlineView.item(atRow: $0) as? FinderFileTreeItem)?.node
            }
        } else {
            // Right-click outside the selection re-anchors it (Finder behavior).
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            nodes = [item.node]
        }
        return contextMenu(nodes)
    }

    // MARK: - Overlay drop targeting

    // Folder under a window-coordinate point (folder row → itself, file row → its parent),
    // resolved like menu(for:). The import overlay sits above the outline, so the outline's
    // own validateDrop never runs for Finder drags — this serves that lookup instead.
    func folderTarget(atWindowPoint windowPoint: NSPoint) -> FileNode? {
        folderItem(atWindowPoint: windowPoint)?.node
    }

    // The overlay can't reach the outline's per-row drop drawing any other way.
    func updateImportHighlight(target: FileNode?) {
        updateDropHighlight(target: target.flatMap { item(forPath: $0.relativePath) })
    }

    private func folderItem(atWindowPoint windowPoint: NSPoint) -> FinderFileTreeItem? {
        guard let outlineView else { return nil }
        let point = outlineView.convert(windowPoint, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0, let item = outlineView.item(atRow: row) as? FinderFileTreeItem
        else { return nil }
        return dropTargetItem(forProposed: item)
    }

    func dropTargetItem(forProposed item: Any?) -> FinderFileTreeItem? {
        guard let item = item as? FinderFileTreeItem else { return nil }
        if item.node.isDirectory { return item }
        return outlineView?.parent(forItem: item) as? FinderFileTreeItem
    }

    // MARK: - Drop highlight roles

    func updateDropHighlight(target: FinderFileTreeItem?) {
        guard target !== dropHighlightTarget else { return }
        let previous = dropHighlightTarget
        dropHighlightTarget = target
        guard let outlineView else { return }
        // Fires per drag event — touch only the rows of the old and new
        // target regions instead of every visible row.
        var affected = affectedRows(of: previous)
        affected.formUnion(affectedRows(of: target))
        for row in affected {
            guard
                let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false)
                    as? FinderFileTreeRowView
            else { continue }
            rowView.dropRole = dropRole(forRow: row)
        }
    }

    private func affectedRows(of target: FinderFileTreeItem?) -> IndexSet {
        guard let outlineView, let target else { return IndexSet() }
        let targetRow = outlineView.row(forItem: target)
        guard targetRow >= 0 else { return IndexSet() }
        return IndexSet(integersIn: memberRowRange(of: targetRow, in: outlineView))
    }

    func dropRole(forRow row: Int) -> FinderFileTreeDropRole {
        guard let outlineView, let target = dropHighlightTarget else { return .none }
        let targetRow = outlineView.row(forItem: target)
        guard targetRow >= 0 else { return .none }
        let members = memberRowRange(of: targetRow, in: outlineView)
        if row == targetRow {
            return .target(extendsBelow: members.upperBound > targetRow)
        }
        if row > targetRow && row <= members.upperBound {
            return .member(isLast: row == members.upperBound)
        }
        return .none
    }

    // The target row plus every following row at a deeper indent level —
    // i.e. the target folder's visible subtree.
    private func memberRowRange(
        of targetRow: Int, in outlineView: NSOutlineView
    ) -> ClosedRange<Int> {
        let targetLevel = outlineView.level(forRow: targetRow)
        var last = targetRow
        var next = targetRow + 1
        while next < outlineView.numberOfRows, outlineView.level(forRow: next) > targetLevel {
            last = next
            next += 1
        }
        return targetRow...last
    }

    // MARK: - Keyboard and mouse

    func requestRenameForSelection() -> Bool {
        guard let outlineView, let onRenameRequest, outlineView.selectedRow >= 0,
            let item = outlineView.item(atRow: outlineView.selectedRow) as? FinderFileTreeItem
        else { return false }
        onRenameRequest(item.node)
        return true
    }

    func requestTrashForSelection() -> Bool {
        guard let outlineView, let onTrashRequest else { return false }
        let nodes = outlineView.selectedRowIndexes.compactMap {
            (outlineView.item(atRow: $0) as? FinderFileTreeItem)?.node
        }
        guard !nodes.isEmpty else { return false }
        onTrashRequest(nodes)
        return true
    }

    @objc func didDoubleClick(_ sender: Any?) {
        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FinderFileTreeItem,
            item.node.isDirectory
        else { return }
        // Clicks on the disclosure triangle already toggled per click — a
        // double-click there must not add a third toggle.
        if let event = NSApp.currentEvent {
            let point = outlineView.convert(event.locationInWindow, from: nil)
            if outlineView.frameOfOutlineCell(atRow: row).contains(point) { return }
        }
        if outlineView.isItemExpanded(item) {
            outlineView.collapseItem(item)
        } else {
            outlineView.expandItem(item)
        }
    }

    // MARK: - Reveal

    func handleReveal(_ request: FileTreeRevealRequest) {
        guard request.id != lastRevealID else { return }
        lastRevealID = request.id
        // Called from updateNSView — the expansion/selection callbacks below
        // must not write SwiftUI state mid view-update.
        Task { @MainActor [weak self] in
            self?.reveal(path: request.path)
        }
    }

    // Selection deliberately reports through onSelect: a reveal makes the
    // revealed row the current item, and adopters route on that.
    func reveal(path: String) {
        guard let outlineView, let item = itemsByPath[path],
            let ancestors = Self.ancestorChain(to: path, in: currentNodes)
        else { return }
        for ancestor in ancestors {
            guard let ancestorItem = itemsByPath[ancestor],
                !outlineView.isItemExpanded(ancestorItem)
            else { continue }
            outlineView.expandItem(ancestorItem)
        }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        scrollRowVisibleThroughAncestors(row)
    }

    // When the tree is embedded in an outer scroll surface its own scroll
    // view has no overflow — `scrollRowToVisible` only reaches the inner
    // clip, so the enclosing scroll view must be driven explicitly.
    func scrollRowVisibleThroughAncestors(_ row: Int) {
        guard let outlineView, row >= 0, row < outlineView.numberOfRows else { return }
        outlineView.scrollRowToVisible(row)
        guard let inner = outlineView.enclosingScrollView,
            let outerDocument = inner.enclosingScrollView?.documentView
        else { return }
        let rect = outerDocument.convert(outlineView.rect(ofRow: row), from: outlineView)
        outerDocument.scrollToVisible(rect)
    }

    // Resolved against the actual tree, not path-string prefixes — ids are
    // opaque and may mix namespaces (Template Manager dual paths).
    nonisolated static func ancestorChain(to path: String, in nodes: [FileNode]) -> [String]? {
        func search(_ nodes: [FileNode], trail: [String]) -> [String]? {
            for node in nodes {
                if node.relativePath == path { return trail }
                if let children = node.children,
                    let found = search(children, trail: trail + [node.relativePath])
                {
                    return found
                }
            }
            return nil
        }
        return search(nodes, trail: [])
    }
}
