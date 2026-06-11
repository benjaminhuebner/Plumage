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

@Suite("IssueSortKey.topOrder")
struct IssueSortKeyTopOrderTests {
    @Test("empty column returns nil")
    func emptyColumn() {
        #expect(IssueSortKey.topOrder(in: []) == nil)
    }

    @Test("column holding only the moving issue returns nil")
    func onlyMovingIssue() {
        let items: [DiscoveredIssue] = [.valid(makeIssue(id: 1, folder: "00001-a", order: 5))]
        #expect(IssueSortKey.topOrder(in: items, excludingFolderName: "00001-a") == nil)
    }

    @Test("explicit orders yield first sort key minus 1")
    func explicitOrders() {
        let items: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", order: 10)),
            .valid(makeIssue(id: 2, folder: "00002-b", order: 3)),
        ]
        #expect(IssueSortKey.topOrder(in: items) == 2.0)
    }

    @Test("missing order falls back to id as sort key")
    func idFallback() {
        let items: [DiscoveredIssue] = [
            .valid(makeIssue(id: 7, folder: "00007-a", order: nil)),
            .valid(makeIssue(id: 12, folder: "00012-b", order: nil)),
        ]
        #expect(IssueSortKey.topOrder(in: items) == 6.0)
    }

    @Test("moving issue's own order does not affect the result")
    func excludesMovingIssue() {
        let items: [DiscoveredIssue] = [
            .valid(makeIssue(id: 1, folder: "00001-a", order: -50)),
            .valid(makeIssue(id: 2, folder: "00002-b", order: 4)),
        ]
        #expect(IssueSortKey.topOrder(in: items, excludingFolderName: "00001-a") == 3.0)
    }

    @Test("order beats id when mixed")
    func mixedKeys() {
        let items: [DiscoveredIssue] = [
            .valid(makeIssue(id: 3, folder: "00003-a", order: nil)),
            .valid(makeIssue(id: 90, folder: "00090-b", order: 1)),
        ]
        #expect(IssueSortKey.topOrder(in: items) == 0.0)
    }

    private func makeIssue(id: Int, folder: String, order: Double?) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: "t",
            type: .feature, status: .done,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: [], order: order
        )
    }
}
