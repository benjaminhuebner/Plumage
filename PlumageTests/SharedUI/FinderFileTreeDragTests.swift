import AppKit
import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("FinderFileTree drag pasteboard roundtrip")
struct FinderFileTreeDragTests {
    private func makeNodes() -> [FileNode] {
        let root = URL(fileURLWithPath: "/tmp/drag-tests")
        let file = FileNode(
            url: root.appending(path: "docs/notes.md"),
            relativePath: "docs/notes.md", name: "notes.md",
            isDirectory: false, children: nil)
        let folder = FileNode(
            url: root.appending(path: "docs"),
            relativePath: "docs", name: "docs",
            isDirectory: true, children: [file])
        return [folder]
    }

    @Test("a dragged row classifies as an internal move, never a Finder copy")
    func internalDragClassifiesAsMove() throws {
        let coordinator = FinderFileTreeCoordinator()
        coordinator.setNodes(makeNodes())
        let item = try #require(coordinator.item(forPath: "docs/notes.md"))

        let writer = try #require(
            coordinator.outlineView(NSOutlineView(), pasteboardWriterForItem: item)
                as? NSPasteboardItem)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let payload = try #require(FinderFileTreeCoordinator.dropPayload(from: pasteboard))
        guard case .internalMove(let urls) = payload else {
            Issue.record("internal drag classified as \(payload)")
            return
        }
        #expect(urls.map(\.path) == ["/tmp/drag-tests/docs/notes.md"])
    }

    @Test("the drag pasteboard also carries the plain file URL for external readers")
    func dragCarriesFileURL() throws {
        let coordinator = FinderFileTreeCoordinator()
        coordinator.setNodes(makeNodes())
        let item = try #require(coordinator.item(forPath: "docs/notes.md"))

        let pasteboardItem = try #require(
            coordinator.outlineView(NSOutlineView(), pasteboardWriterForItem: item)
                as? NSPasteboardItem)
        #expect(pasteboardItem.string(forType: .fileURL) != nil)
    }

    @Test("canDrag exclusion produces no pasteboard writer")
    func canDragExclusion() throws {
        let coordinator = FinderFileTreeCoordinator()
        coordinator.setNodes(makeNodes())
        coordinator.canDrag = { _ in false }
        let item = try #require(coordinator.item(forPath: "docs/notes.md"))
        #expect(coordinator.outlineView(NSOutlineView(), pasteboardWriterForItem: item) == nil)
    }
}

@MainActor
@Suite("FinderFileTree drop delegate")
struct FinderFileTreeDropDelegateTests {
    private func makeNodes() -> [FileNode] {
        let root = URL(fileURLWithPath: "/tmp/drop-tests")
        let file = FileNode(
            url: root.appending(path: "docs/notes.md"),
            relativePath: "docs/notes.md", name: "notes.md",
            isDirectory: false, children: nil)
        let docs = FileNode(
            url: root.appending(path: "docs"),
            relativePath: "docs", name: "docs",
            isDirectory: true, children: [file])
        let assets = FileNode(
            url: root.appending(path: "assets"),
            relativePath: "assets", name: "assets",
            isDirectory: true, children: [])
        return [docs, assets]
    }

    private func makeOutline(coordinator: FinderFileTreeCoordinator) -> NSOutlineView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outlineView = outline
        coordinator.setNodes(makeNodes())
        outline.expandItem(nil, expandChildren: true)
        return outline
    }

    private func draggingInfo(sourcePath: String) throws -> StubDraggingInfo {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("drop-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let payload = FileTreeDragPayload(url: URL(fileURLWithPath: sourcePath))
        let item = NSPasteboardItem()
        item.setData(
            try JSONEncoder().encode(payload),
            forType: FinderFileTreeCoordinator.internalDragType)
        pasteboard.writeObjects([item])
        return StubDraggingInfo(pasteboard: pasteboard)
    }

    @Test("validateDrop resolves a folder target and reports .move")
    func validateDropMovesOntoFolder() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        var validated: (payload: FileTreeDropPayload, target: FileNode?)?
        coordinator.validateDrop = { payload, target in
            validated = (payload, target)
            return true
        }
        let target = try #require(coordinator.item(forPath: "assets"))

        let operation = coordinator.outlineView(
            outline, validateDrop: try draggingInfo(sourcePath: "/tmp/drop-tests/docs/notes.md"),
            proposedItem: target, proposedChildIndex: NSOutlineViewDropOnItemIndex)

        #expect(operation == .move)
        #expect(validated?.target?.relativePath == "assets")
    }

    @Test("validateDrop rejects a folder dragged onto its own descendant")
    func validateDropRejectsAncestorIntoSelf() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        coordinator.validateDrop = { _, _ in true }
        let target = try #require(coordinator.item(forPath: "docs"))

        let operation = coordinator.outlineView(
            outline, validateDrop: try draggingInfo(sourcePath: "/tmp/drop-tests/docs"),
            proposedItem: target, proposedChildIndex: NSOutlineViewDropOnItemIndex)

        #expect(operation.isEmpty)
    }

    @Test("validateDrop returns no operation when the adopter declines")
    func validateDropAdopterDecline() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        coordinator.validateDrop = { _, _ in false }
        let target = try #require(coordinator.item(forPath: "assets"))

        let operation = coordinator.outlineView(
            outline, validateDrop: try draggingInfo(sourcePath: "/tmp/drop-tests/docs/notes.md"),
            proposedItem: target, proposedChildIndex: NSOutlineViewDropOnItemIndex)

        #expect(operation.isEmpty)
    }

    @Test("acceptDrop hands payload and target to the adopter")
    func acceptDropCallsAdopter() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        var dropped: (payload: FileTreeDropPayload, target: FileNode?)?
        coordinator.onDrop = { payload, target in
            dropped = (payload, target)
            return true
        }
        let target = try #require(coordinator.item(forPath: "assets"))

        let accepted = coordinator.outlineView(
            outline, acceptDrop: try draggingInfo(sourcePath: "/tmp/drop-tests/docs/notes.md"),
            item: target, childIndex: NSOutlineViewDropOnItemIndex)

        #expect(accepted)
        #expect(dropped?.target?.relativePath == "assets")
        guard case .internalMove(let sources) = dropped?.payload else {
            Issue.record("expected internal move, got \(String(describing: dropped?.payload))")
            return
        }
        #expect(sources.map(\.path) == ["/tmp/drop-tests/docs/notes.md"])
    }
}

// Minimal NSDraggingInfo so the drop delegate is testable without a real
// HID drag session — only draggingPasteboard carries meaning here.
final class StubDraggingInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}
