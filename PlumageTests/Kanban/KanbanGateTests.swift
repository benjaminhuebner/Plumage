import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("ProjectKanbanModel inactive gate")
struct KanbanGateTests {
    @Test("defers snapshot application while inactive and applies the latest on reactivation")
    func coalescesWhileInactive() {
        let url = URL(filePath: "/tmp/kanban-gate-probe")
        let model = ProjectKanbanModel(mutator: { _, _, _, _ in })
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let issueB = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)

        model.ingest([.valid(issueA)], projectURL: url)
        #expect(model.issues.count == 1)

        model.setActive(false)
        model.ingest([.valid(issueA), .valid(issueB)], projectURL: url)
        #expect(model.issues.count == 1)

        model.setActive(true)
        #expect(model.issues.count == 2)
        #expect(model.issues.map(\.id).sorted() == ["00001-a", "00002-b"])
    }
}
