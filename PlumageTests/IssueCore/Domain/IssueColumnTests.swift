import Testing

@testable import Plumage

@Suite("IssueColumn")
struct IssueColumnTests {
    @Test("allCases is the render order: Todo, In Progress, Waiting for Review, Done")
    func renderOrder() {
        #expect(IssueColumn.allCases == [.todo, .inProgress, .waitingForReview, .done])
    }

    @Test("name returns the canonical English label per case")
    func nameLabels() {
        #expect(IssueColumn.todo.name == "Todo")
        #expect(IssueColumn.inProgress.name == "In Progress")
        #expect(IssueColumn.waitingForReview.name == "Waiting for Review")
        #expect(IssueColumn.done.name == "Done")
    }

    @Test("id is the raw value and stable across calls")
    func identifiableStability() {
        for column in IssueColumn.allCases {
            #expect(column.id == column.rawValue)
            #expect(column.id == column.id)
        }
    }
}
