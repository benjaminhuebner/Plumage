import Foundation
import Testing

@testable import Plumage

struct FileTreeDiffTests {
    private static let root = URL(fileURLWithPath: "/tmp/diff-tests")

    private func file(_ path: String, empty: Bool = false) -> FileNode {
        FileNode(
            url: Self.root.appending(path: path),
            relativePath: path,
            name: (path as NSString).lastPathComponent,
            isDirectory: false,
            children: nil,
            isEmptyContextFile: empty)
    }

    private func folder(_ path: String, _ children: [FileNode]) -> FileNode {
        FileNode(
            url: Self.root.appending(path: path),
            relativePath: path,
            name: (path as NSString).lastPathComponent,
            isDirectory: true,
            children: children)
    }

    @Test func identicalTreesProduceNoDiff() {
        let tree = [folder(".claude", [file(".claude/CLAUDE.md")])]
        #expect(FileTreeDiff.diff(old: tree, new: tree).isEmpty)
    }

    @Test func insertionAtRootIsReportedWithNewIndex() throws {
        let old = [file("a.md"), file("c.md")]
        let new = [file("a.md"), file("b.md"), file("c.md")]
        let diffs = FileTreeDiff.diff(old: old, new: new)
        let diff = try #require(diffs.first)
        #expect(diffs.count == 1)
        #expect(diff.parentPath == nil)
        #expect(diff.insertedIndices == [1])
        #expect(diff.removedIndices.isEmpty)
        #expect(!diff.needsReorder)
    }

    @Test func removalInsideFolderIsScopedToThatParent() throws {
        let old = [folder(".claude", [file(".claude/a.md"), file(".claude/b.md")])]
        let new = [folder(".claude", [file(".claude/a.md")])]
        let diffs = FileTreeDiff.diff(old: old, new: new)
        let diff = try #require(diffs.first)
        #expect(diffs.count == 1)
        #expect(diff.parentPath == ".claude")
        #expect(diff.removedIndices == [1])
        #expect(diff.insertedIndices.isEmpty)
    }

    @Test func renameIsRemovalPlusInsertion() throws {
        let old = [file("old.md")]
        let new = [file("new.md")]
        let diff = try #require(FileTreeDiff.diff(old: old, new: new).first)
        #expect(diff.removedIndices == [0])
        #expect(diff.insertedIndices == [0])
        #expect(diff.updatedPaths.isEmpty)
    }

    @Test func shallowPayloadChangeIsAnUpdateNotAStructuralEdit() throws {
        let old = [file(".claude/CLAUDE.md")]
        let new = [file(".claude/CLAUDE.md", empty: true)]
        let diff = try #require(FileTreeDiff.diff(old: old, new: new).first)
        #expect(diff.updatedPaths == [".claude/CLAUDE.md"])
        #expect(diff.removedIndices.isEmpty)
        #expect(diff.insertedIndices.isEmpty)
        #expect(!diff.needsReorder)
    }

    @Test func grandchildChangeDoesNotMarkParentUpdated() throws {
        let old = [folder(".claude", [folder(".claude/docs", [file(".claude/docs/a.md")])])]
        let new = [
            folder(
                ".claude",
                [folder(".claude/docs", [file(".claude/docs/a.md"), file(".claude/docs/b.md")])])
        ]
        let diffs = FileTreeDiff.diff(old: old, new: new)
        let diff = try #require(diffs.first)
        #expect(diffs.count == 1)
        #expect(diff.parentPath == ".claude/docs")
        #expect(diff.insertedIndices == [1])
    }

    @Test func reorderOfKeptSiblingsSetsNeedsReorder() throws {
        let old = [file("a.md"), file("b.md")]
        let new = [file("b.md"), file("a.md")]
        let diff = try #require(FileTreeDiff.diff(old: old, new: new).first)
        #expect(diff.needsReorder)
        #expect(diff.removedIndices.isEmpty)
        #expect(diff.insertedIndices.isEmpty)
    }

    @Test func removedFolderDoesNotRecurseIntoItsChildren() {
        let old = [folder("gone", [file("gone/a.md")]), file("stay.md")]
        let new = [file("stay.md")]
        let diffs = FileTreeDiff.diff(old: old, new: new)
        #expect(diffs.count == 1)
        #expect(diffs.first?.parentPath == nil)
        #expect(diffs.first?.removedIndices == [0])
    }

    @Test func mixedInsertAndRemoveInOneParent() throws {
        let old = [file("a.md"), file("b.md"), file("c.md")]
        let new = [file("a.md"), file("c.md"), file("d.md")]
        let diff = try #require(FileTreeDiff.diff(old: old, new: new).first)
        #expect(diff.removedIndices == [1])
        #expect(diff.insertedIndices == [2])
        #expect(!diff.needsReorder)
    }

    @Test func ancestorChainWalksTheTreeFromRootDown() {
        let tree = [
            folder(".claude", [folder(".claude/docs", [file(".claude/docs/notes.md")])]),
            file("top.md"),
        ]
        #expect(
            FinderFileTreeCoordinator.ancestorChain(to: ".claude/docs/notes.md", in: tree)
                == [".claude", ".claude/docs"])
        #expect(FinderFileTreeCoordinator.ancestorChain(to: "top.md", in: tree)?.isEmpty == true)
        #expect(FinderFileTreeCoordinator.ancestorChain(to: "missing.md", in: tree) == nil)
    }

    @Test func topmostSourcesDropsDescendantsOfDraggedFolders() {
        let folder = URL(fileURLWithPath: "/tmp/tree/docs")
        let child = URL(fileURLWithPath: "/tmp/tree/docs/inner/a.md")
        let sibling = URL(fileURLWithPath: "/tmp/tree/other.md")
        let result = FinderFileTreeCoordinator.topmostSources([folder, child, sibling])
        #expect(result == [folder, sibling])
    }

    @Test func topmostSourcesKeepsUnrelatedPrefixSiblings() {
        // "docs-archive" shares the string prefix "docs" but is no descendant.
        let folder = URL(fileURLWithPath: "/tmp/tree/docs")
        let lookalike = URL(fileURLWithPath: "/tmp/tree/docs-archive/a.md")
        let result = FinderFileTreeCoordinator.topmostSources([folder, lookalike])
        #expect(result == [folder, lookalike])
    }

    // Template Manager trees mix namespaces: folders carry output paths,
    // leaves carry store paths — ancestor resolution must not assume prefixes.
    @Test func ancestorChainSupportsMixedPathNamespaces() {
        let tree = [
            folder(".claude", [folder(".claude/docs", [file("docs/notes.md")])])
        ]
        #expect(
            FinderFileTreeCoordinator.ancestorChain(to: "docs/notes.md", in: tree)
                == [".claude", ".claude/docs"])
    }
}
