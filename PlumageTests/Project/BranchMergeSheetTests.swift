import Foundation
import Testing

@testable import Plumage

@Suite("BranchMergeSheet rules")
struct BranchMergeSheetTests {
    @Test("merge is enabled for squash with a subject")
    func squashWithSubjectEnabled() {
        #expect(
            !BranchMergeSheet.mergeDisabled(
                isMerging: false, mergeCompleted: false,
                mergeMode: .squash, trimmedSubject: "Merge a into b"))
    }

    @Test("squash with an empty subject disables merge")
    func squashEmptySubjectDisabled() {
        #expect(
            BranchMergeSheet.mergeDisabled(
                isMerging: false, mergeCompleted: false,
                mergeMode: .squash, trimmedSubject: ""))
    }

    @Test("fast-forward needs no subject")
    func fastForwardNeedsNoSubject() {
        #expect(
            !BranchMergeSheet.mergeDisabled(
                isMerging: false, mergeCompleted: false,
                mergeMode: .fastForward, trimmedSubject: ""))
    }

    @Test("an in-flight merge disables the button")
    func inFlightDisables() {
        #expect(
            BranchMergeSheet.mergeDisabled(
                isMerging: true, mergeCompleted: false,
                mergeMode: .fastForward, trimmedSubject: ""))
    }

    @Test("a completed merge with a pending notice disables re-merging")
    func completedMergeDisablesReMerge() {
        #expect(
            BranchMergeSheet.mergeDisabled(
                isMerging: false, mergeCompleted: true,
                mergeMode: .fastForward, trimmedSubject: ""))
    }

    @Test("notFastForward maps to a switch-to-squash hint, not the PR sheet's rebase button")
    func notFastForwardHintsSquash() throws {
        let message = try #require(
            BranchMergeSheet.errorMessage(
                for: .notFastForward(targetBranch: "main", issueBranch: "feature/a")))
        #expect(message.contains("main"))
        #expect(message.contains("feature/a"))
        #expect(message.contains("Switch to Squash"))
        #expect(!message.contains("Rebase & Merge"))
    }

    @Test("other errors pass their display message through")
    func otherErrorsPassThrough() {
        let error = GitMergeError.workingTreeDirty(files: ["Plumage/Foo.swift"])
        #expect(BranchMergeSheet.errorMessage(for: error) == error.localizedDescription)
    }

    @Test("no error yields no banner message")
    func nilErrorYieldsNil() {
        #expect(BranchMergeSheet.errorMessage(for: nil) == nil)
    }
}
