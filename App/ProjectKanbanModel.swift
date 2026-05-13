import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ProjectKanbanModel {
    private(set) var issues: [DiscoveredIssue] = []
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
        await withTaskCancellationHandler {
            for await snapshot in producer.snapshots {
                withAnimation(.smooth(duration: 0.4)) { self.issues = snapshot }
            }
        } onCancel: {
            Task { await producer.stop() }
        }
    }
}
