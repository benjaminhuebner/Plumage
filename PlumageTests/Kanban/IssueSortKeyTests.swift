import Foundation
import Testing

@testable import Plumage

@Suite("IssueColumn.canonicalDropStatus")
struct IssueColumnCanonicalDropStatusTests {
    @Test("todo maps to approved")
    func todoMapsApproved() {
        #expect(IssueColumn.todo.canonicalDropStatus == .approved)
    }

    @Test("inProgress maps to inProgress")
    func inProgressMapsInProgress() {
        #expect(IssueColumn.inProgress.canonicalDropStatus == .inProgress)
    }

    @Test("waitingForReview maps to waitingForReview")
    func waitingForReviewMapsWaitingForReview() {
        #expect(IssueColumn.waitingForReview.canonicalDropStatus == .waitingForReview)
    }

    @Test("done maps to done")
    func doneMapsDone() {
        #expect(IssueColumn.done.canonicalDropStatus == .done)
    }
}

@Suite("IssueSortKey.midOrder")
struct IssueSortKeyMidOrderTests {
    @Test("both neighbors averages them")
    func bothNeighbors() {
        #expect(IssueSortKey.midOrder(above: 2.0, below: 4.0, fallbackID: 99) == 3.0)
    }

    @Test("above-only adds 1")
    func aboveOnly() {
        #expect(IssueSortKey.midOrder(above: 5.0, below: nil, fallbackID: 99) == 6.0)
    }

    @Test("below-only subtracts 1")
    func belowOnly() {
        #expect(IssueSortKey.midOrder(above: nil, below: 5.0, fallbackID: 99) == 4.0)
    }

    @Test("no neighbors uses fallback id")
    func noNeighbors() {
        #expect(IssueSortKey.midOrder(above: nil, below: nil, fallbackID: 42) == 42.0)
    }
}
