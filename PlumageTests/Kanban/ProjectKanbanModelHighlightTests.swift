import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.highlight")
@MainActor
struct ProjectKanbanModelHighlightTests {
    @Test("highlight sets the id then resets after the duration elapses")
    func setsThenResets() async throws {
        let clock = ManualClock()
        let model = ProjectKanbanModel(
            producerFactory: { _ in fatalError("unused") },
            clock: clock,
            highlightDuration: .seconds(1)
        )

        model.highlight(folderName: "00003-foo")
        #expect(model.highlightedIssueID == "00003-foo")

        try await clock.waitForWaiterCount(1)
        clock.advance(by: .seconds(1))

        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.highlightedIssueID == nil }
        }
    }

    @Test("a second highlight call cancels the first and resets only after the second duration")
    func reHighlightCancelsPrevious() async throws {
        let clock = ManualClock()
        let model = ProjectKanbanModel(
            producerFactory: { _ in fatalError("unused") },
            clock: clock,
            highlightDuration: .seconds(1)
        )

        model.highlight(folderName: "00001-a")
        try await clock.waitForWaiterCount(1)
        model.highlight(folderName: "00002-b")
        #expect(model.highlightedIssueID == "00002-b")

        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(900))
        // Still highlighted — only 900ms in.
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.highlightedIssueID == "00002-b")

        clock.advance(by: .milliseconds(200))
        try await waitUntil(timeout: .seconds(2)) {
            await MainActor.run { model.highlightedIssueID == nil }
        }
    }
}
