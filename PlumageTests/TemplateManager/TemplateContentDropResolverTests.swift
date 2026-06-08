import Foundation
import Testing

@testable import Plumage

// The content tree's nodes carry a dual path (folders hold their output path, file
// leaves hold their override-store path), so the resolver derives the target store
// directory per node kind. Pure, no disk.
@Suite("TemplateContentDropResolver")
struct TemplateContentDropResolverTests {
    private func folder(_ output: String) -> FileNode {
        FileNode(
            url: URL(filePath: "/x/\(output)"), relativePath: output,
            name: (output as NSString).lastPathComponent, isDirectory: true, children: [])
    }

    private func file(store: String) -> FileNode {
        FileNode(
            url: URL(filePath: "/x/\(store)"), relativePath: store,
            name: (store as NSString).lastPathComponent, isDirectory: false, children: nil)
    }

    @Test("a folder row targets its own store directory")
    func folderTargetsSelf() {
        #expect(TemplateContentDropResolver.targetStoreDir(for: folder(".claude/hooks")) == "hooks")
    }

    @Test("a file row targets its containing store directory")
    func fileTargetsParent() {
        #expect(TemplateContentDropResolver.targetStoreDir(for: file(store: "hooks/x.sh")) == "hooks")
    }

    @Test("the .claude root folder is a real, valid store target (#00084)")
    func claudeRootIsRealTarget() {
        #expect(TemplateContentDropResolver.targetStoreDir(for: folder(".claude")) == ".claude")
        #expect(
            TemplateContentDropResolver.targetStoreDir(for: folder(".claude"), scope: .template("macOS"))
                == "templates/macOS/.claude")
    }

    @Test("a base-root file can move into the real .claude root (#00084)")
    func looseFileMovesIntoClaude() {
        // Bug 2 regression: dropping a store-root file onto `.claude` is a real move now,
        // no longer a silent no-op into the same folder.
        #expect(!TemplateContentDropResolver.rejectsMove(storePath: ".editorconfig", intoStoreDir: ".claude"))
    }

    @Test("an arbitrary .claude file targets the .claude store dir, not the root (#00084)")
    func arbitraryClaudeFileTargetsClaude() {
        #expect(
            TemplateContentDropResolver.targetStoreDir(for: file(store: ".claude/bla.md")) == ".claude")
    }

    @Test("a file in an internal store namespace is not a valid target")
    func internalNamespaceRejected() {
        #expect(TemplateContentDropResolver.targetStoreDir(for: file(store: "configs/swift-format")) == nil)
    }

    @Test("storePath resolves a folder's output path back to the store, a file as-is")
    func storePathDualMapping() {
        #expect(TemplateContentDropResolver.storePath(for: folder(".claude/skills/my")) == "skills/my")
        #expect(TemplateContentDropResolver.storePath(for: file(store: "docs/intro.md")) == "docs/intro.md")
    }

    @Test("moving a folder into itself or its own subtree is rejected")
    func rejectsSelfAndSubtree() {
        #expect(TemplateContentDropResolver.rejectsMove(storePath: "skills/my", intoStoreDir: "skills/my"))
        #expect(
            TemplateContentDropResolver.rejectsMove(storePath: "skills/my", intoStoreDir: "skills/my/sub"))
    }

    @Test("dropping a file into the folder it already lives in is a no-op")
    func rejectsNoOp() {
        #expect(TemplateContentDropResolver.rejectsMove(storePath: "hooks/x.sh", intoStoreDir: "hooks"))
    }

    @Test("a genuine cross-folder move is allowed")
    func allowsCrossFolderMove() {
        #expect(!TemplateContentDropResolver.rejectsMove(storePath: "hooks/x.sh", intoStoreDir: "docs"))
    }
}
