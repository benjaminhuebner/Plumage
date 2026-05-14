import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ProjectKanbanModel {
    nonisolated enum DropTarget: Equatable, Sendable {
        case column(IssueColumn)
        case aboveCard(folderName: String, column: IssueColumn)
        case belowCard(folderName: String, column: IssueColumn)
    }

    nonisolated enum DropMutation: Equatable, Sendable {
        case noop
        case apply(newStatus: IssueStatus, newOrder: SetValue<Double?>)
    }

    typealias Mutator = @Sendable (URL, IssueStatus?, SetValue<Double?>, Date) throws -> Void

    private(set) var issues: [DiscoveredIssue] = []
    private(set) var groupedIssues: [IssueColumn: [DiscoveredIssue]] = [:]
    private(set) var highlightedIssueID: String?
    private(set) var lastDropError: String?

    private let producerFactory: @Sendable (URL) -> IssueSnapshotProducer
    private let highlightClock: any Clock<Duration>
    private let highlightDuration: Duration
    private let mutator: Mutator
    private var highlightTask: Task<Void, Never>?
    private var dropTask: Task<Void, Never>?

    init(
        producerFactory: @escaping @Sendable (URL) -> IssueSnapshotProducer = {
            IssueSnapshotProducer(projectURL: $0)
        },
        clock: any Clock<Duration> = ContinuousClock(),
        highlightDuration: Duration = .seconds(1),
        mutator: @escaping Mutator = { url, status, order, now in
            try FrontmatterMutator.mutate(
                specURL: url, newStatus: status, newOrder: order, now: now)
        }
    ) {
        self.producerFactory = producerFactory
        self.highlightClock = clock
        self.highlightDuration = highlightDuration
        self.mutator = mutator
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
            self?.highlightedIssueID = nil
        }
    }

    func clearDropError() {
        lastDropError = nil
    }

    #if DEBUG
    func _setIssuesForTesting(_ issues: [DiscoveredIssue]) {
        self.issues = issues
        self.groupedIssues = Self.group(issues)
    }
    #endif

    // Cancels any prior in-flight drop and schedules a new one. Views must
    // use this instead of spawning unstructured Tasks in `dropDestination`
    // closures — drops fired in quick succession could otherwise commit to
    // disk out of order relative to the UI snapshot they read.
    func dispatchDrop(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) {
        dropTask?.cancel()
        dropTask = Task { [weak self] in
            await self?.performDrop(payload, to: target, projectURL: projectURL)
        }
    }

    func performDrop(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) async {
        guard let issue = lookupValidIssue(payload.folderName) else { return }
        let mutation = Self.computeMutation(
            issue: issue, target: target, snapshot: issues)
        switch mutation {
        case .noop:
            return
        case .apply(let newStatus, let newOrder):
            let specURL =
                projectURL
                .appendingPathComponent(".claude/issues")
                .appendingPathComponent(issue.folderName)
                .appendingPathComponent("spec.md")
            let mutatorFn = mutator
            do {
                try await Task.detached {
                    try mutatorFn(specURL, newStatus, newOrder, Date())
                }.value
            } catch {
                lastDropError = error.localizedDescription
            }
        }
    }

    nonisolated static func computeMutation(
        issue: Issue,
        target: DropTarget,
        snapshot: [DiscoveredIssue]
    ) -> DropMutation {
        let issueColumn = issue.column

        switch target {
        case .column(let column):
            if column == issueColumn { return .noop }
            return .apply(newStatus: column.canonicalDropStatus, newOrder: .set(nil))

        case .aboveCard(let folderName, let column):
            if folderName == issue.folderName { return .noop }
            return reorderMutation(
                issue: issue,
                issueColumn: issueColumn,
                targetFolderName: folderName,
                targetColumn: column,
                snapshot: snapshot,
                insertAbove: true
            )

        case .belowCard(let folderName, let column):
            if folderName == issue.folderName { return .noop }
            return reorderMutation(
                issue: issue,
                issueColumn: issueColumn,
                targetFolderName: folderName,
                targetColumn: column,
                snapshot: snapshot,
                insertAbove: false
            )
        }
    }

    nonisolated private static func reorderMutation(
        issue: Issue,
        issueColumn: IssueColumn,
        targetFolderName: String,
        targetColumn: IssueColumn,
        snapshot: [DiscoveredIssue],
        insertAbove: Bool
    ) -> DropMutation {
        let columnItems =
            snapshot
            .filter { $0.column == targetColumn && $0.id != issue.folderName }
            .sortedForKanban()
        guard let targetIndex = columnItems.firstIndex(where: { $0.id == targetFolderName }) else {
            return .noop
        }
        let aboveItem: DiscoveredIssue?
        let belowItem: DiscoveredIssue?
        if insertAbove {
            aboveItem = targetIndex > 0 ? columnItems[targetIndex - 1] : nil
            belowItem = columnItems[targetIndex]
        } else {
            aboveItem = columnItems[targetIndex]
            belowItem = targetIndex + 1 < columnItems.count ? columnItems[targetIndex + 1] : nil
        }
        let aboveOrder = aboveItem?.orderValue ?? aboveItem.map { Double($0.idValue) }
        let belowOrder = belowItem?.orderValue ?? belowItem.map { Double($0.idValue) }
        let newOrder = IssueSortKey.midOrder(
            above: aboveOrder, below: belowOrder, fallbackID: issue.id)
        let statusChanges = targetColumn != issueColumn
        let newStatus: IssueStatus = statusChanges ? targetColumn.canonicalDropStatus : issue.status
        return .apply(newStatus: newStatus, newOrder: .set(newOrder))
    }

    private func lookupValidIssue(_ folderName: String) -> Issue? {
        for item in issues {
            if case .valid(let issue) = item, issue.folderName == folderName {
                return issue
            }
        }
        return nil
    }

    private static func group(
        _ issues: [DiscoveredIssue]
    ) -> [IssueColumn: [DiscoveredIssue]] {
        Dictionary(grouping: issues, by: \.column)
    }
}

nonisolated extension Issue {
    var column: IssueColumn {
        switch status {
        case .draft, .approved, .blocked: .todo
        case .inProgress: .inProgress
        case .waitingForReview: .waitingForReview
        case .done: .done
        }
    }
}
