import Foundation
import Testing

@testable import Plumage

@Suite("BlockerResolution")
struct BlockerResolutionTests {
    @Test(
        "blocker status maps to state: done is done, everything else is open",
        arguments: [
            (IssueStatus.draft, BlockerState.open),
            (IssueStatus.approved, BlockerState.open),
            (IssueStatus.inProgress, BlockerState.open),
            (IssueStatus.waitingForReview, BlockerState.open),
            (IssueStatus.blocked, BlockerState.open),
            (IssueStatus.done, BlockerState.done),
        ]
    )
    func statusMapping(status: IssueStatus, expected: BlockerState) {
        let blocker = makeIssue(id: 42, folder: "00042-blocker", status: status)
        let resolved = BlockerResolution.resolve(
            blockedBy: ["00042-blocker"],
            of: "00001-self",
            index: BlockerResolution.index([.valid(blocker)])
        )
        #expect(resolved.map(\.state) == [expected])
        #expect(resolved.first?.id == 42)
        #expect(resolved.first?.title == "Blocker 42")
    }

    @Test("dangling reference resolves to missing, never errors")
    func danglingIsMissing() {
        let resolved = BlockerResolution.resolve(
            blockedBy: ["00999-gone"],
            of: "00001-self",
            index: [:]
        )
        #expect(
            resolved == [
                ResolvedBlocker(folderName: "00999-gone", state: .missing, id: nil, title: nil)
            ])
        #expect(
            BlockerResolution.openBlockers(
                blockedBy: ["00999-gone"], of: "00001-self", index: [:]
            ).isEmpty
        )
    }

    @Test("self-reference is ignored")
    func selfIgnored() {
        let me = makeIssue(id: 1, folder: "00001-self", status: .approved)
        let resolved = BlockerResolution.resolve(
            blockedBy: ["00001-self"],
            of: "00001-self",
            index: BlockerResolution.index([.valid(me)])
        )
        #expect(resolved.isEmpty)
    }

    @Test("duplicate entries resolve once, order preserved")
    func duplicatesResolveOnce() {
        let first = makeIssue(id: 2, folder: "00002-a", status: .approved)
        let second = makeIssue(id: 3, folder: "00003-b", status: .done)
        let resolved = BlockerResolution.resolve(
            blockedBy: ["00002-a", "00003-b", "00002-a"],
            of: "00001-self",
            index: BlockerResolution.index([.valid(first), .valid(second)])
        )
        #expect(resolved.map(\.folderName) == ["00002-a", "00003-b"])
    }

    @Test("cycle: both sides resolve as open without traversal")
    func cycleBothOpen() {
        let first = makeIssue(id: 1, folder: "00001-a", status: .approved, blockedBy: ["00002-b"])
        let second = makeIssue(id: 2, folder: "00002-b", status: .approved, blockedBy: ["00001-a"])
        let index = BlockerResolution.index([.valid(first), .valid(second)])
        let openForA = BlockerResolution.openBlockers(
            blockedBy: first.blockedBy, of: first.folderName, index: index)
        let openForB = BlockerResolution.openBlockers(
            blockedBy: second.blockedBy, of: second.folderName, index: index)
        #expect(openForA.map(\.folderName) == ["00002-b"])
        #expect(openForB.map(\.folderName) == ["00001-a"])
    }

    @Test("invalid-frontmatter blocker counts as open with folder-name fallback")
    func invalidBlockerIsOpen() {
        let folder = URL(filePath: "/tmp/issues/00005-broken")
        let resolved = BlockerResolution.resolve(
            blockedBy: ["00005-broken"],
            of: "00001-self",
            index: BlockerResolution.index([.invalid(folder: folder, error: .missingFrontmatter)])
        )
        #expect(
            resolved == [
                ResolvedBlocker(folderName: "00005-broken", state: .open, id: nil, title: nil)
            ])
    }

    @Test("empty blockedBy resolves to nothing")
    func emptyList() {
        let resolved = BlockerResolution.resolve(blockedBy: [], of: "00001-self", index: [:])
        #expect(resolved.isEmpty)
    }

    private func makeIssue(
        id: Int, folder: String, status: IssueStatus, blockedBy: [String] = []
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "Blocker \(id)",
            type: .feature, status: status,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: [], blockedBy: blockedBy
        )
    }
}
