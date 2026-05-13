import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ProjectKanbanModel {
    private(set) var issues: [DiscoveredIssue] = []
    private(set) var groupedIssues: [IssueColumn: [DiscoveredIssue]] = [:]
    private let producerFactory: @Sendable (URL) -> IssueSnapshotProducer

    init(
        producerFactory: @escaping @Sendable (URL) -> IssueSnapshotProducer = {
            IssueSnapshotProducer(projectURL: $0)
        }
    ) {
        self.producerFactory = producerFactory
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

    private static func group(
        _ issues: [DiscoveredIssue]
    ) -> [IssueColumn: [DiscoveredIssue]] {
        Dictionary(grouping: issues, by: \.column)
    }
}
