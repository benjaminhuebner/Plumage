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
