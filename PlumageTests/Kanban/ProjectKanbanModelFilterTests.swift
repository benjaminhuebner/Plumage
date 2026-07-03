import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ProjectKanbanModel filtering")
struct ProjectKanbanModelFilterTests {
    private let url = URL(filePath: "/tmp/kanban-filter-probe")

    @Test("active filter narrows groupedIssues but leaves issues untouched")
    func filterNarrowsGroups() {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let auth = makeIssue(id: 1, folder: "00001-auth", title: "User auth", labels: ["backend"])
        let board = makeIssue(id: 2, folder: "00002-board", title: "Board polish", labels: ["ui"])
        model.ingest([.valid(auth), .valid(board)], projectURL: url)

        model.filter.text = "auth"

        #expect(model.issues.count == 2)
        let visible = model.groupedIssues.values.flatMap(\.self).map(\.id)
        #expect(visible == ["00001-auth"])
    }

    @Test("a snapshot arriving while filtered only surfaces matching cards")
    func liveIngestRespectsFilter() {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let auth = makeIssue(id: 1, folder: "00001-auth", title: "User auth", labels: [])
        model.ingest([.valid(auth)], projectURL: url)
        model.filter.selectedLabels = ["ui"]
        #expect(model.groupedIssues.values.flatMap(\.self).isEmpty)

        let matching = makeIssue(id: 2, folder: "00002-board", title: "Board", labels: ["ui"])
        model.ingest([.valid(auth), .valid(matching)], projectURL: url)

        let visible = model.groupedIssues.values.flatMap(\.self).map(\.id)
        #expect(visible == ["00002-board"])
        #expect(model.issues.count == 2)
    }

    @Test("clearFilter restores every card and keeps the id pad width")
    func clearRestores() {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let auth = makeIssue(id: 1, folder: "00001-auth", title: "User auth", labels: [])
        model.ingest([.valid(auth)], projectURL: url)
        model.filter.idPadWidth = 6
        model.filter.text = "no-match-anywhere"
        #expect(model.groupedIssues.values.flatMap(\.self).isEmpty)

        model.clearFilter()

        #expect(!model.filter.isActive)
        #expect(model.filter.idPadWidth == 6)
        #expect(model.groupedIssues.values.flatMap(\.self).count == 1)
    }

    @Test("totalColumnCounts report the unfiltered board")
    func totalCountsUnfiltered() {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let auth = makeIssue(id: 1, folder: "00001-auth", title: "User auth", labels: [])
        let board = makeIssue(id: 2, folder: "00002-board", title: "Board", labels: ["ui"])
        model.ingest([.valid(auth), .valid(board)], projectURL: url)
        model.filter.text = "auth"

        let column = DiscoveredIssue.valid(auth).column
        #expect(model.totalColumnCounts[column] == 2)
        #expect(model.groupedIssues[column]?.count == 1)
    }

    @Test("availableFilterLabels union all valid issues, sorted")
    func availableLabels() {
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let auth = makeIssue(id: 1, folder: "00001-auth", title: "A", labels: ["ui", "backend"])
        let board = makeIssue(id: 2, folder: "00002-board", title: "B", labels: ["ui", "v0.1"])
        model.ingest([.valid(auth), .valid(board)], projectURL: url)
        #expect(model.availableFilterLabels == ["backend", "ui", "v0.1"])
    }

    private func makeIssue(
        id: Int, folder: String, title: String, labels: [String]
    ) -> Plumage.Issue {
        Plumage.Issue(
            id: id, folderName: folder, title: title,
            type: .feature, status: .approved,
            created: .distantPast, updated: .distantPast,
            branch: "issue/\(folder)", labels: labels
        )
    }
}
