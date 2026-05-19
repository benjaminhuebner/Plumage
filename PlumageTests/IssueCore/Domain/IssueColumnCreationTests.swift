import Testing

@testable import Plumage

@Suite("IssueColumn.primaryStatusForCreation")
struct IssueColumnCreationTests {
    @Test("Each column maps to its canonical creation status")
    func columnToCreationStatus() {
        #expect(IssueColumn.todo.primaryStatusForCreation == .draft)
        #expect(IssueColumn.inProgress.primaryStatusForCreation == .inProgress)
        #expect(IssueColumn.waitingForReview.primaryStatusForCreation == .waitingForReview)
        #expect(IssueColumn.done.primaryStatusForCreation == .done)
    }
}
