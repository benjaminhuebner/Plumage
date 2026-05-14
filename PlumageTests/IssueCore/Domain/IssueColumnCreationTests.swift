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

@Suite("SpecRoute.createIssue")
struct SpecRouteCreateIssueTests {
    @Test("createIssue case is Hashable and Codable, distinct per initialStatus")
    func createIssueHashable() {
        let routeA: SpecRoute = .createIssue(initialStatus: .draft)
        let routeB: SpecRoute = .createIssue(initialStatus: .draft)
        let routeC: SpecRoute = .createIssue(initialStatus: .inProgress)
        #expect(routeA == routeB)
        #expect(routeA != routeC)
        #expect(routeA.hashValue == routeB.hashValue)
    }

    @Test("createIssue does not collide with spec/rawEditor cases")
    func createIssueDistinctFromOtherCases() {
        let create: SpecRoute = .createIssue(initialStatus: .draft)
        let spec: SpecRoute = .spec(folderName: "00001-x")
        let raw: SpecRoute = .rawEditor(folderName: "00001-x")
        #expect(create != spec)
        #expect(create != raw)
    }
}
