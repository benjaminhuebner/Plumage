import AppKit
import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("FinderFileTree batch updates")
struct FinderFileTreeBatchUpdateTests {
    private func makeOutline(coordinator: FinderFileTreeCoordinator) -> NSOutlineView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outlineView = outline
        return outline
    }

    private func node(_ relativePath: String, children: [FileNode]? = nil) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: "/tmp/batch-tests").appending(path: relativePath),
            relativePath: relativePath,
            name: String(relativePath.split(separator: "/").last ?? ""),
            isDirectory: children != nil,
            children: children)
    }

    @Test("a snapshot mixing reorder and insert/remove under different parents applies cleanly")
    func mixedReorderAndStructuralSnapshot() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        coordinator.setNodes([
            node("a", children: [node("a/one"), node("a/two")]),
            node("b", children: [node("b/x")]),
            node("stale"),
        ])
        outline.expandItem(nil, expandChildren: true)
        #expect(outline.numberOfRows == 6)

        coordinator.setNodes([
            node("a", children: [node("a/two"), node("a/one")]),
            node("b", children: [node("b/x"), node("b/y")]),
        ])

        let itemA = try #require(coordinator.item(forPath: "a"))
        let itemB = try #require(coordinator.item(forPath: "b"))
        #expect(itemA.children.map(\.node.relativePath) == ["a/two", "a/one"])
        #expect(itemB.children.map(\.node.relativePath) == ["b/x", "b/y"])
        #expect(coordinator.item(forPath: "stale") == nil)
        #expect(outline.numberOfChildren(ofItem: itemA) == 2)
        #expect(outline.numberOfChildren(ofItem: itemB) == 2)
        #expect(outline.numberOfChildren(ofItem: nil) == 2)
        #expect(outline.numberOfRows == 6)
    }

    @Test("a pure reorder snapshot keeps item identity for kept rows")
    func reorderKeepsItemIdentity() throws {
        let coordinator = FinderFileTreeCoordinator()
        let outline = makeOutline(coordinator: coordinator)
        coordinator.setNodes([
            node("a", children: [node("a/one"), node("a/two")])
        ])
        outline.expandItem(nil, expandChildren: true)
        let before = try #require(coordinator.item(forPath: "a/one"))

        coordinator.setNodes([
            node("a", children: [node("a/two"), node("a/one")])
        ])

        let after = try #require(coordinator.item(forPath: "a/one"))
        #expect(before === after)
        #expect(outline.numberOfRows == 3)
    }
}
