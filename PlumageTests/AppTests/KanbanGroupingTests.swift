import Foundation
import Testing

@testable import Plumage

@Suite("Kanban grouping")
struct KanbanGroupingTests {
    @Test("Dictionary(grouping:by:\\.column) buckets every status into the expected column")
    func groupingMatchesColumns() throws {
        let issues: [DiscoveredIssue] = [
            .valid(sample(id: 1, folder: "00001-draft", status: .draft)),
            .valid(sample(id: 2, folder: "00002-approved", status: .approved)),
            .valid(sample(id: 3, folder: "00003-blocked", status: .blocked)),
            .invalid(
                folder: URL(filePath: "/x/.claude/issues/00004-broken"),
                error: .invalidEnumValue(field: "status", value: "aproved")
            ),
            .valid(sample(id: 5, folder: "00005-in-progress", status: .inProgress)),
            .valid(sample(id: 6, folder: "00006-waiting", status: .waitingForReview)),
            .valid(sample(id: 7, folder: "00007-done", status: .done)),
        ]

        let grouped = Dictionary(grouping: issues, by: \.column)

        let todo = try #require(grouped[.todo])
        #expect(todo.count == 4)
        #expect(
            todo.map(folderOf)
                == ["00001-draft", "00002-approved", "00003-blocked", "00004-broken"])

        let inProgress = try #require(grouped[.inProgress])
        #expect(inProgress.count == 1)
        #expect(folderOf(inProgress[0]) == "00005-in-progress")

        let waiting = try #require(grouped[.waitingForReview])
        #expect(waiting.count == 1)
        #expect(folderOf(waiting[0]) == "00006-waiting")

        let done = try #require(grouped[.done])
        #expect(done.count == 1)
        #expect(folderOf(done[0]) == "00007-done")
    }

    private func sample(id: Int, folder: String, status: IssueStatus) -> Plumage.Issue {
        Plumage.Issue(
            id: id,
            folderName: folder,
            title: "Title \(id)",
            type: .feature,
            status: status,
            created: .distantPast,
            updated: .distantPast,
            branch: "issue/\(folder)",
            labels: [],
            model: nil
        )
    }

    private func folderOf(_ item: DiscoveredIssue) -> String {
        switch item {
        case .valid(let issue): return issue.folderName
        case .invalid(let folder, _): return folder.lastPathComponent
        }
    }
}
