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
    var rowContent: ((FileNode) -> AnyView)?

    nonisolated static let internalDragType = NSPasteboard.PasteboardType(
        UTType.plumageFileTreeDrag.identifier)

    private(set) var rootItems: [FinderFileTreeItem] = []
    private var itemsByPath: [String: FinderFileTreeItem] = [:]
    private var currentNodes: [FileNode] = []
    private(set) var expandedPaths: Set<String> = []
    // Suppresses the expansion-change callback while expansion is being
    // *applied* from SwiftUI state — only user-initiated toggles report back.
    private var isApplyingExpansion = false
    private var isApplyingSelection = false
    private var lastRevealID: UUID?
    private var lastSelectedPath: String?
    private weak var dropHighlightTarget: FinderFileTreeItem?

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

    // No prefix shortcuts here: folder and file ids can live in different
    // path namespaces (Template Manager's output vs. store paths).
    private func childNodes(forParentPath parentPath: String?) -> [FileNode] {
        guard let parentPath else { return currentNodes }
        func find(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.relativePath == parentPath { return node }
                if let children = node.children, let found = find(children) {
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
        outlineView.scrollRowToVisible(row)
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

    func outlineView(
        _ outlineView: NSOutlineView, pasteboardWriterForItem item: Any
    ) -> (any NSPasteboardWriting)? {
        guard let item = item as? FinderFileTreeItem else { return nil }
        if let canDrag, !canDrag(item.node) { return nil }
        guard let data = try? JSONEncoder().encode(FileTreeDragPayload(url: item.node.url))
        else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: Self.internalDragType)
        pasteboardItem.setString(item.node.url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?, proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let validateDrop, let payload = Self.dropPayload(from: info.draggingPasteboard)
        else { return [] }
        let target = dropTargetItem(forProposed: item)
        // Always drop ON the resolved folder row — native highlight lands
        // exactly there instead of an insertion line between rows.
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        if case .internalMove(let sources) = payload {
            let targetURL = target?.node.url
            for source in sources where Self.isAncestorOrSelf(source, of: targetURL) {
                updateDropHighlight(target: nil)
                return []
            }
        }
        guard validateDrop(payload, target?.node) else {
            updateDropHighlight(target: nil)
            return []
        }
        updateDropHighlight(target: target)
        switch payload {
        case .internalMove: return .move
        case .finderCopy: return .copy
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
        item: Any?, childIndex index: Int
    ) -> Bool {
        updateDropHighlight(target: nil)
        guard let onDrop, let payload = Self.dropPayload(from: info.draggingPasteboard)
        else { return false }
        let target = item as? FinderFileTreeItem
        return onDrop(payload, target?.node)
    }

    private func dropTargetItem(forProposed item: Any?) -> FinderFileTreeItem? {
        guard let item = item as? FinderFileTreeItem else { return nil }
        if item.node.isDirectory { return item }
        return outlineView?.parent(forItem: item) as? FinderFileTreeItem
    }

    // MARK: - Drop highlight roles

    func updateDropHighlight(target: FinderFileTreeItem?) {
        guard target !== dropHighlightTarget else { return }
        dropHighlightTarget = target
        guard let outlineView else { return }
        for row in 0..<outlineView.numberOfRows {
            guard
                let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false)
                    as? FinderFileTreeRowView
            else { continue }
            rowView.dropRole = dropRole(forRow: row)
        }
    }

    private func dropRole(forRow row: Int) -> FinderFileTreeDropRole {
        guard let outlineView, let target = dropHighlightTarget else { return .none }
        let targetRow = outlineView.row(forItem: target)
        guard targetRow >= 0 else { return .none }
        let targetLevel = outlineView.level(forRow: targetRow)
        var lastMemberRow = targetRow
        var next = targetRow + 1
        while next < outlineView.numberOfRows, outlineView.level(forRow: next) > targetLevel {
            lastMemberRow = next
            next += 1
        }
        if row == targetRow {
            return .target(extendsBelow: lastMemberRow > targetRow)
        }
        if row > targetRow && row <= lastMemberRow {
            return .member(isLast: row == lastMemberRow)
        }
        return .none
    }

    nonisolated static func dropPayload(from pasteboard: NSPasteboard) -> FileTreeDropPayload? {
        var internalSources: [URL] = []
        var finderURLs: [URL] = []
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: internalDragType),
                let payload = try? JSONDecoder().decode(FileTreeDragPayload.self, from: data)
            {
                internalSources.append(payload.url)
            } else if let urlString = item.string(forType: .fileURL),
                let url = URL(string: urlString)
            {
                finderURLs.append(url.standardizedFileURL)
            }
        }
        if !internalSources.isEmpty { return .internalMove(topmostSources(internalSources)) }
        if !finderURLs.isEmpty { return .finderCopy(finderURLs) }
        return nil
    }

    // A selection holding a folder and its own descendant moves only the
    // folder — moving both would race the descendant against its parent.
    nonisolated static func topmostSources(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            !urls.contains { other in
                other.standardizedFileURL.path != url.standardizedFileURL.path
                    && isAncestorOrSelf(other, of: url)
            }
        }
    }

    // nil target = tree root, which can never sit inside a dragged item.
    nonisolated static func isAncestorOrSelf(_ source: URL, of target: URL?) -> Bool {
        guard let target else { return false }
        let sourcePath = source.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        return targetPath == sourcePath || targetPath.hasPrefix(sourcePath + "/")
    }
}

extension FinderFileTreeCoordinator: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("FinderFileTreeRow")
        let rowView: FinderFileTreeRowView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: nil)
            as? FinderFileTreeRowView
        {
            rowView = recycled
        } else {
            rowView = FinderFileTreeRowView()
            rowView.identifier = identifier
        }
        // A row scrolled into view mid-drag must pick up its role.
        rowView.dropRole = dropRole(forRow: outlineView.row(forItem: item))
        return rowView
    }

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

    func outlineView(
        _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
    ) -> String? {
        (item as? FinderFileTreeItem)?.node.name
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection,
            let outlineView = notification.object as? NSOutlineView
        else { return }
        let row = outlineView.selectedRow
        let node = row >= 0 ? (outlineView.item(atRow: row) as? FinderFileTreeItem)?.node : nil
        // Deselects keep the previous anchor: the collapse path needs to know
        // what WAS selected after the outline has already cleared it.
        if let node { lastSelectedPath = node.relativePath }
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
        reanchorSelection(afterCollapsing: item)
    }

    // Finder behavior: collapsing a folder that hides the selection selects
    // the folder itself — without this the outline just drops the selection
    // and adopters blank their detail pane.
    private func reanchorSelection(afterCollapsing item: FinderFileTreeItem) {
        guard let outlineView, outlineView.selectedRowIndexes.isEmpty,
            let last = lastSelectedPath, Self.subtree(of: item, contains: last)
        else { return }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private static func subtree(of item: FinderFileTreeItem, contains path: String) -> Bool {
        for child in item.children {
            if child.node.relativePath == path { return true }
            if subtree(of: child, contains: path) { return true }
        }
        return false
    }
}

enum FinderFileTreeDropRole: Equatable {
    case none
    case target(extendsBelow: Bool)
    case member(isLast: Bool)
}

// The stock drop-on feedback is a hairline ring that reads as a glitch —
// replace it with the Xcode-navigator look: a full accent fill on the target
// folder row plus a light wash over its visible children, one rounded region.
final class FinderFileTreeRowView: NSTableRowView {
    var dropRole: FinderFileTreeDropRole = .none {
        didSet {
            guard oldValue != dropRole else { return }
            needsDisplay = true
            // The accent fill is a dark surface in any appearance — flip the
            // hosted SwiftUI row to dark so its text reads white on it.
            let isTarget = if case .target = dropRole { true } else { false }
            for subview in subviews {
                subview.appearance = isTarget ? NSAppearance(named: .darkAqua) : nil
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dropRole = .none
    }

    // Drawing is driven entirely by `dropRole` (the coordinator knows the
    // whole target region); the stock per-row feedback must stay silent.
    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {}

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        let inset = bounds.insetBy(dx: 6, dy: 0)
        switch dropRole {
        case .none:
            return
        case .target(let extendsBelow):
            let rect =
                extendsBelow
                ? NSRect(x: inset.minX, y: 0, width: inset.width, height: bounds.height)
                : inset.insetBy(dx: 0, dy: 1)
            NSColor.controlAccentColor.setFill()
            Self.roundedPath(
                rect, topRadius: 6, bottomRadius: extendsBelow ? 0 : 6
            ).fill()
        case .member(let isLast):
            let rect = NSRect(
                x: inset.minX, y: 0, width: inset.width,
                height: isLast ? bounds.height - 1 : bounds.height)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            Self.roundedPath(rect, topRadius: 0, bottomRadius: isLast ? 6 : 0).fill()
        }
    }

    // NSBezierPath has no per-corner radii — the target region needs square
    // edges where it meets the member rows below it.
    private static func roundedPath(
        _ rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        // Flipped view: minY = top edge on screen.
        let topLeft = NSPoint(x: rect.minX, y: rect.minY)
        let topRight = NSPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = NSPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = NSPoint(x: rect.minX, y: rect.maxY)
        path.move(to: NSPoint(x: rect.minX, y: rect.minY + topRadius))
        path.appendArc(from: topLeft, to: topRight, radius: topRadius)
        path.appendArc(from: topRight, to: bottomRight, radius: topRadius)
        path.appendArc(from: bottomRight, to: bottomLeft, radius: bottomRadius)
        path.appendArc(from: bottomLeft, to: topLeft, radius: bottomRadius)
        path.close()
        return path
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
