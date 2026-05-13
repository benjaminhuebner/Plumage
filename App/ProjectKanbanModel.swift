import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ProjectKanbanModel {
    private(set) var issues: [DiscoveredIssue] = []
    private(set) var groupedIssues: [IssueColumn: [DiscoveredIssue]] = [:]
    private(set) var highlightedIssueID: String?
    private let producerFactory: @Sendable (URL) -> IssueSnapshotProducer
    private let highlightClock: any Clock<Duration>
    private let highlightDuration: Duration
    private var highlightTask: Task<Void, Never>?

    init(
        producerFactory: @escaping @Sendable (URL) -> IssueSnapshotProducer = {
            IssueSnapshotProducer(projectURL: $0)
        },
        clock: any Clock<Duration> = ContinuousClock(),
        highlightDuration: Duration = .seconds(1)
    ) {
        self.producerFactory = producerFactory
        self.highlightClock = clock
        self.highlightDuration = highlightDuration
    }

    func run(projectURL: URL) async {
        let producer = producerFactory(projectURL)
        await producer.start()
        for await snapshot in producer.snapshots {
            let groups = Self.group(snapshot)
            withAnimation(.smooth(duration: 0.4)) {
                self.issues = snapshot
                self.groupedIssues = groups
            }
        }
        await producer.stop()
    }

    func highlight(folderName: String) {
        highlightTask?.cancel()
        highlightedIssueID = folderName
        let clock = highlightClock
        let duration = highlightDuration
        highlightTask = Task { [weak self] in
            try? await clock.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.highlightedIssueID = nil
            }
        }
    }

    private static func group(
        _ issues: [DiscoveredIssue]
    ) -> [IssueColumn: [DiscoveredIssue]] {
        Dictionary(grouping: issues, by: \.column)
    }
}
