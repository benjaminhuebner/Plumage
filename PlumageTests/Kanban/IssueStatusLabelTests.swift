import Testing

@testable import Plumage

@Suite("IssueStatus.label")
struct IssueStatusLabelTests {
    @Test(
        "maps to its Title-Case label",
        arguments: [
            (IssueStatus.draft, "Draft"),
            (.approved, "Approved"),
            (.inProgress, "In Progress"),
            (.waitingForReview, "Waiting for Review"),
            (.done, "Done"),
            (.blocked, "Blocked"),
        ] as [(IssueStatus, String)]
    )
    func labelMapping(status: IssueStatus, expected: String) {
        #expect(status.label == expected)
    }

    @Test("argument list covers every IssueStatus case")
    func argumentsCoverAllCases() {
        // Compile-time guard: if a new case is added, this fails until the
        // parameterized argument list above is updated.
        let covered: Set<IssueStatus> = [
            .draft, .approved, .inProgress, .waitingForReview, .done, .blocked,
        ]
        #expect(covered.count == IssueStatus.allCases.count)
    }
}
