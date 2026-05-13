import Foundation
import Testing

@testable import Plumage

@Suite("DiscoveredIssue+Column")
struct DiscoveredIssueColumnTests {
    @Test("every IssueStatus maps to the expected column", arguments: IssueStatus.allCases)
    func everyStatusHasAColumn(status: IssueStatus) {
        let issue = DiscoveredIssue.valid(sample(status: status))
        let expected: IssueColumn
        switch status {
        case .draft, .approved, .blocked: expected = .todo
        case .inProgress: expected = .inProgress
        case .waitingForReview: expected = .waitingForReview
        case .done: expected = .done
        }
        #expect(issue.column == expected)
    }

    @Test(".invalid maps to .todo")
    func invalidIsTodo() {
        let invalid = DiscoveredIssue.invalid(
            folder: URL(filePath: "/x/00009-broken"),
            error: .missingFrontmatter
        )
        #expect(invalid.column == .todo)
    }

    @Test("isBlocked is true only for valid issues with status == .blocked")
    func isBlockedSemantics() {
        for status in IssueStatus.allCases {
            let issue = DiscoveredIssue.valid(sample(status: status))
            #expect(issue.isBlocked == (status == .blocked))
        }

        let invalid = DiscoveredIssue.invalid(
            folder: URL(filePath: "/x/00010-x"),
            error: .missingFrontmatter
        )
        #expect(invalid.isBlocked == false)
    }

    private func sample(status: IssueStatus) -> Plumage.Issue {
        Plumage.Issue(
            id: 1,
            folderName: "00001-foo",
            title: "Title",
            type: .feature,
            status: status,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/00001-foo",
            labels: [],
            model: nil
        )
    }
}
