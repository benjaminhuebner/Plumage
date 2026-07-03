import AppKit
import os

extension FinderFileTreeCoordinator: NSOutlineViewDataSource {
    nonisolated private static let logger = Logger(
        subsystem: "com.plumage", category: "FinderFileTree")

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
        else {
            Self.logger.warning(
                "drag payload encode failed for \(item.node.relativePath, privacy: .public)")
            return nil
        }
        let pasteboardItem = NSPasteboardItem()
        // Only the custom type — not .fileURL. The .fileURL-only import catcher must stay
        // blind to in-tree drags so they reach the outline; dropPayload reads the custom
        // type first and external drag-out is off, so .fileURL was redundant.
        pasteboardItem.setData(data, forType: Self.internalDragType)
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
        autoscrollThroughAncestors(info)
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

    // Embedded mode: the inner scroll view has no overflow, so AppKit's own
    // drag autoscroll never fires — drive the outer scroll surface instead.
    private func autoscrollThroughAncestors(_ info: any NSDraggingInfo) {
        guard let outlineView,
            let inner = outlineView.enclosingScrollView,
            let outerScroll = inner.enclosingScrollView,
            let outerDocument = outerScroll.documentView
        else { return }
        let point = outerDocument.convert(info.draggingLocation, from: nil)
        let visible = outerScroll.documentVisibleRect
        let margin: CGFloat = 24
        let probeY: CGFloat
        if point.y < visible.minY + margin {
            probeY = point.y - margin
        } else if point.y > visible.maxY - margin {
            probeY = point.y + margin
        } else {
            return
        }
        outerDocument.scrollToVisible(NSRect(x: visible.midX, y: probeY, width: 1, height: 1))
    }

    nonisolated static func dropPayload(from pasteboard: NSPasteboard) -> FileTreeDropPayload? {
        var internalSources: [URL] = []
        var finderURLs: [URL] = []
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: internalDragType) {
                if let payload = try? JSONDecoder().decode(FileTreeDragPayload.self, from: data) {
                    internalSources.append(payload.url)
                    continue
                }
                logger.warning("internal drag payload failed to decode — treating as Finder drop")
            }
            if let urlString = item.string(forType: .fileURL),
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
