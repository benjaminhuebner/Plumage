import AppKit
import SwiftUI

enum FinderFileTreeStyle {
    // Fully transparent: the sidebar's Liquid Glass must show through.
    case sidebar
    case inset
}

nonisolated enum FileTreeDropPayload: Equatable, Sendable {
    case internalMove([URL])
    case finderCopy([URL])

    var urls: [URL] {
        switch self {
        case .internalMove(let urls), .finderCopy(let urls): return urls
        }
    }
}

struct FileTreeRevealRequest: Equatable {
    let id: UUID
    let path: String

    init(path: String) {
        self.id = UUID()
        self.path = path
    }
}

struct FinderFileTree<RowContent: View>: NSViewRepresentable {
    let nodes: [FileNode]
    let style: FinderFileTreeStyle
    @Binding var expandedPaths: Set<String>
    var selectedPath: String?
    var revealRequest: FileTreeRevealRequest?
    // Set when the tree is embedded in an outer scroll surface: internal
    // scrolling turns off and the outline's content height is reported so
    // the host can size the frame.
    var onContentHeightChange: ((CGFloat) -> Void)?
    var contextMenu: (([FileNode]) -> NSMenu?)?
    var onRenameRequest: ((FileNode) -> Void)?
    var onTrashRequest: (([FileNode]) -> Void)?
    var canDrag: ((FileNode) -> Bool)?
    var validateDrop: ((FileTreeDropPayload, FileNode?) -> Bool)?
    var onDrop: ((FileTreeDropPayload, FileNode?) -> Bool)?
    let onSelect: (FileNode?) -> Void
    @ViewBuilder let rowContent: (FileNode) -> RowContent

    func makeCoordinator() -> FinderFileTreeCoordinator {
        FinderFileTreeCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = FinderFileTreeOutlineView()
        outline.headerView = nil
        outline.focusRingType = .none
        outline.rowSizeStyle = .default
        outline.usesAutomaticRowHeights = true
        outline.allowsMultipleSelection = true
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
        scroll.hasVerticalScroller = onContentHeightChange == nil
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        if onContentHeightChange != nil {
            scroll.verticalScrollElasticity = .none
            context.coordinator.observeContentHeight(of: outline)
        }

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
        outline.target = context.coordinator
        outline.doubleAction = #selector(FinderFileTreeCoordinator.didDoubleClick(_:))
        outline.onReturnKey = { [weak coordinator = context.coordinator] in
            coordinator?.requestRenameForSelection() ?? false
        }
        outline.onDeleteKey = { [weak coordinator = context.coordinator] in
            coordinator?.requestTrashForSelection() ?? false
        }
        // The native feedback paints a wider fill than the custom group
        // region and pokes out around it — all drop drawing is row-view-owned.
        outline.draggingDestinationFeedbackStyle = .none
        outline.registerForDraggedTypes([.fileURL, FinderFileTreeCoordinator.internalDragType])
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.menuProvider = { [weak coordinator = context.coordinator] event in
            coordinator?.menu(for: event)
        }
        outline.onDragSessionEnded = { [weak coordinator = context.coordinator] in
            coordinator?.updateDropHighlight(target: nil)
        }
        context.coordinator.outlineView = outline
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onExpansionChange = { expandedPaths = $0 }
        coordinator.onRenameRequest = onRenameRequest
        coordinator.onTrashRequest = onTrashRequest
        coordinator.canDrag = canDrag
        coordinator.validateDrop = validateDrop
        coordinator.onDrop = onDrop
        coordinator.contextMenu = contextMenu
        coordinator.onContentHeightChange = onContentHeightChange
        coordinator.rowContent = { node in AnyView(rowContent(node)) }
        // Expansion state lands before the nodes so a freshly built tree is
        // expanded in the same pass that creates its items.
        coordinator.setExpandedPaths(expandedPaths)
        coordinator.setNodes(nodes)
        coordinator.setSelectedPath(selectedPath)
        if let revealRequest {
            coordinator.handleReveal(revealRequest)
        }
    }
}

final class FinderFileTreeOutlineView: NSOutlineView {
    var onReturnKey: (() -> Bool)?
    var onDeleteKey: (() -> Bool)?
    var menuProvider: ((NSEvent) -> NSMenu?)?
    var onDragSessionEnded: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event) ?? super.menu(for: event)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragSessionEnded?()
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDragSessionEnded?()
        super.draggingEnded(sender)
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .some(.carriageReturn), .some(.enter):
            if onReturnKey?() == true { return }
        case .some(.delete), .some(.deleteForward), .some(.backspace):
            if onDeleteKey?() == true { return }
        default:
            break
        }
        super.keyDown(with: event)
    }
}

#Preview("Sidebar style") {
    @Previewable @State var expanded: Set<String> = [".claude"]
    FinderFileTree(
        nodes: FinderFileTreePreviewData.nodes,
        style: .sidebar,
        expandedPaths: $expanded,
        onSelect: { _ in },
        rowContent: { node in
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
        }
    )
    .frame(width: 260, height: 360)
}

#Preview("Inset style") {
    @Previewable @State var expanded: Set<String> = []
    FinderFileTree(
        nodes: FinderFileTreePreviewData.nodes,
        style: .inset,
        expandedPaths: $expanded,
        onSelect: { _ in },
        rowContent: { node in
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
        }
    )
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
