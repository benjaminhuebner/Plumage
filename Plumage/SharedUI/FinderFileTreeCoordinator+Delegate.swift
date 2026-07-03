import AppKit

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
        cell.setAccessibilityLabel(item.node.name)
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
        // Keyboard navigation auto-scrolls only the inner clip — follow
        // through the outer scroll surface too.
        scrollRowVisibleThroughAncestors(row)
        onSelect?(node)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        defer { reportContentHeight() }
        guard !isApplyingExpansion,
            let item = notification.userInfo?["NSObject"] as? FinderFileTreeItem
        else { return }
        expandedPaths.insert(item.node.relativePath)
        onExpansionChange?(expandedPaths)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        defer { reportContentHeight() }
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
