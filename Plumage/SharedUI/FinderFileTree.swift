import AppKit
import SwiftUI

enum FinderFileTreeStyle {
    // Fully transparent: the sidebar's Liquid Glass must show through.
    case sidebar
    case inset
}

struct FinderFileTree<RowContent: View>: NSViewRepresentable {
    let nodes: [FileNode]
    let style: FinderFileTreeStyle
    let onSelect: (FileNode?) -> Void
    @ViewBuilder let rowContent: (FileNode) -> RowContent

    func makeCoordinator() -> FinderFileTreeCoordinator {
        FinderFileTreeCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = nil
        outline.focusRingType = .none
        outline.rowSizeStyle = .default
        outline.usesAutomaticRowHeights = true
        outline.allowsMultipleSelection = false
        outline.allowsColumnReordering = false
        outline.allowsColumnResizing = false
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = false
        outline.indentationMarkerFollowsCell = true

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("FinderFileTreeColumn"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        switch style {
        case .sidebar:
            outline.style = .sourceList
            outline.backgroundColor = .clear
        case .inset:
            outline.style = .inset
            outline.backgroundColor = .clear
        }

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        context.coordinator.outlineView = outline
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.rowContent = { node in AnyView(rowContent(node)) }
        coordinator.setNodes(nodes)
    }
}

#Preview("Sidebar style") {
    FinderFileTree(
        nodes: FinderFileTreePreviewData.nodes,
        style: .sidebar,
        onSelect: { _ in }
    ) { node in
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
    }
    .frame(width: 260, height: 360)
}

#Preview("Inset style") {
    FinderFileTree(
        nodes: FinderFileTreePreviewData.nodes,
        style: .inset,
        onSelect: { _ in }
    ) { node in
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
    }
    .frame(width: 320, height: 360)
}

enum FinderFileTreePreviewData {
    static var nodes: [FileNode] {
        let root = URL(fileURLWithPath: "/tmp/plumage-preview")
        func file(_ path: String) -> FileNode {
            FileNode(
                url: root.appending(path: path),
                relativePath: path,
                name: (path as NSString).lastPathComponent,
                isDirectory: false,
                children: nil)
        }
        func folder(_ path: String, _ children: [FileNode]) -> FileNode {
            FileNode(
                url: root.appending(path: path),
                relativePath: path,
                name: (path as NSString).lastPathComponent,
                isDirectory: true,
                children: children)
        }
        return [
            folder(
                ".claude",
                [
                    file(".claude/CLAUDE.md"),
                    folder(
                        ".claude/docs",
                        [
                            file(".claude/docs/PROJECT.md"),
                            file(".claude/docs/decisions.md"),
                        ]),
                    folder(".claude/hooks", [file(".claude/hooks/format.sh")]),
                ]),
            file(".mcp.json"),
        ]
    }
}
