import Testing

@testable import Plumage

@Suite("MergeBranchSection.mergeDisabled")
struct MergeBranchSectionTests {
    @Test("only an in-flight merge, a blocking run, or an empty squash subject disable merge")
    func disableInputs() {
        #expect(
            !MergeBranchSection.mergeDisabled(
                isMerging: false, blockingRunIssue: nil, mergeMode: .squash,
                trimmedSubject: "Add feature"))
        #expect(
            MergeBranchSection.mergeDisabled(
                isMerging: true, blockingRunIssue: nil, mergeMode: .squash,
                trimmedSubject: "Add feature"))
        #expect(
            MergeBranchSection.mergeDisabled(
                isMerging: false, blockingRunIssue: "00043-other", mergeMode: .squash,
                trimmedSubject: "Add feature"))
        #expect(
            MergeBranchSection.mergeDisabled(
                isMerging: false, blockingRunIssue: nil, mergeMode: .squash, trimmedSubject: ""))
        #expect(
            !MergeBranchSection.mergeDisabled(
                isMerging: false, blockingRunIssue: nil, mergeMode: .fastForward,
                trimmedSubject: ""))
    }

    @Test("evidence state is not an input to the merge-disable decision")
    func evidenceCannotDisableMerge() {
        let decision: (Bool, String?, GitMergeMode, String) -> Bool =
            MergeBranchSection.mergeDisabled(
                isMerging:blockingRunIssue:mergeMode:trimmedSubject:)
        #expect(!decision(false, nil, .squash, "Subject"))
    }
}
