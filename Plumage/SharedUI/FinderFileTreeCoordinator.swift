import AppKit
import SwiftUI

// NSOutlineView tracks items by object identity — value-type nodes would
// collapse expansion and selection on every rebuild.
final class FinderFileTreeItem {
    private(set) var node: FileNode
    private(set) var children: [FinderFileTreeItem]

    init(node: FileNode) {
        self.node = node
        self.children = (node.children ?? []).map(FinderFileTreeItem.init)
    }
}

final class FinderFileTreeCoordinator: NSObject {
    weak var outlineView: NSOutlineView?
    var onSelect: ((FileNode?) -> Void)?
    var rowContent: ((FileNode) -> AnyView)?

    private(set) var rootItems: [FinderFileTreeItem] = []
    private var currentNodes: [FileNode] = []

    func setNodes(_ nodes: [FileNode]) {
        guard nodes != currentNodes else { return }
        currentNodes = nodes
        rootItems = nodes.map(FinderFileTreeItem.init)
        outlineView?.reloadData()
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
