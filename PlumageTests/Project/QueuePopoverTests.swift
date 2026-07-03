import Foundation
import Testing

@testable import Plumage

struct QueuePopoverTests {
    @Test("entries keep FIFO order with 1-based positions")
    func fifoPositions() {
        let queue = [
            QueuedImplementRun(issue: "00020-first", agentPid: 100),
            QueuedImplementRun(issue: "00021-second", agentPid: 101),
            QueuedImplementRun(issue: "00022-third", agentPid: 102),
        ]

        let entries = QueueDisplayBuilder.entries(from: queue) { _ in false }

        #expect(entries.map(\.position) == [1, 2, 3])
        #expect(entries.map(\.slug) == ["00020-first", "00021-second", "00022-third"])
    }

    @Test("ownership classification marks only tab-owned slugs cancelable")
    func ownershipClassification() {
        let queue = [
            QueuedImplementRun(issue: "00020-plumage-owned", agentPid: 100),
            QueuedImplementRun(issue: "00021-external", agentPid: 101),
        ]
        let owned: Set<String> = ["00020-plumage-owned"]

        let entries = QueueDisplayBuilder.entries(from: queue) { owned.contains($0) }

        #expect(entries.first { $0.slug == "00020-plumage-owned" }?.isCancelable == true)
        #expect(entries.first { $0.slug == "00021-external" }?.isCancelable == false)
    }

    @Test("empty queue yields no entries")
    func emptyQueue() {
        #expect(QueueDisplayBuilder.entries(from: []) { _ in true }.isEmpty)
    }
}
