import Testing

@testable import Plumage

@Suite("IssueStatus.label")
struct IssueStatusLabelTests {
    @Test("all cases map to their Title-Case label")
    func allCasesMap() {
        let expected: [IssueStatus: String] = [
            .draft: "Draft",
            .approved: "Approved",
            .inProgress: "In Progress",
            .waitingForReview: "Waiting for Review",
            .done: "Done",
            .blocked: "Blocked",
        ]
        for status in IssueStatus.allCases {
            #expect(status.label == expected[status])
        }
        #expect(IssueStatus.allCases.count == expected.count)
    }
}
