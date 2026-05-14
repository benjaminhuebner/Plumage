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
    private(set) var pendingDropFolderName: String?
    private(set) var pendingDropExpectedStatus: IssueStatus?
    private(set) var pendingDropExpectedOrder: SetValue<Double?>?

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
            let reconciled = Self.reconcile(
                incoming: snapshot,
                pending: pendingDropFolderName,
                expectedStatus: pendingDropExpectedStatus,
                expectedOrder: pendingDropExpectedOrder
            )
            let groups = Self.group(reconciled.snapshot)
            withAnimation(.smooth(duration: 0.4)) {
                self.issues = reconciled.snapshot
                self.groupedIssues = groups
            }
            if reconciled.pendingCleared {
                pendingDropFolderName = nil
                pendingDropExpectedStatus = nil
                pendingDropExpectedOrder = nil
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
    // use this instead of spawning unstructured Tasks in gesture callbacks —
    // drops fired in quick succession could otherwise commit to disk out of
    // order relative to the UI snapshot they read.
    func dispatchDrop(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) {
        dropTask?.cancel()
        dropTask = Task { [weak self] in
            await self?.performDropOptimistic(payload, to: target, projectURL: projectURL)
        }
    }

    func performDropOptimistic(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) async {
        guard let issue = lookupValidIssue(payload.folderName) else { return }
        let mutation = Self.computeMutation(
            issue: issue, target: target, snapshot: issues)
        guard case .apply(let newStatus, let newOrder) = mutation else { return }

        let priorIssues = issues
        let updated = makeOptimisticUpdate(
            issue: issue, newStatus: newStatus, newOrder: newOrder)
        pendingDropFolderName = issue.folderName
        pendingDropExpectedStatus = newStatus
        pendingDropExpectedOrder = newOrder
        withAnimation(.smooth(duration: 0.18)) {
            issues = Self.replace(issues, folderName: issue.folderName, with: updated)
            groupedIssues = Self.group(issues)
        }

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
            withAnimation(.smooth) {
                issues = priorIssues
                groupedIssues = Self.group(priorIssues)
            }
            pendingDropFolderName = nil
            pendingDropExpectedStatus = nil
            pendingDropExpectedOrder = nil
            lastDropError = error.localizedDescription
        }
    }

    nonisolated static func reconcile(
        incoming: [DiscoveredIssue],
        pending: String?,
        expectedStatus: IssueStatus?,
        expectedOrder: SetValue<Double?>?
    ) -> (snapshot: [DiscoveredIssue], pendingCleared: Bool) {
        guard let pending else { return (incoming, false) }
        guard let idx = incoming.firstIndex(where: { $0.id == pending }) else {
            return (incoming, true)
        }
        guard case .valid(let item) = incoming[idx] else {
            return (incoming, false)
        }
        let statusMatch = expectedStatus == nil || item.status == expectedStatus
        let orderMatch: Bool
        switch expectedOrder {
        case .none, .some(.keep):
            orderMatch = true
        case .some(.set(let expected)):
            orderMatch = item.order == expected
        }
        if statusMatch && orderMatch {
            return (incoming, true)
        }
        let patchedStatus = expectedStatus ?? item.status
        let patchedOrder: Double?
        switch expectedOrder {
        case .none, .some(.keep):
            patchedOrder = item.order
        case .some(.set(let value)):
            patchedOrder = value
        }
        let patched = Issue(
            id: item.id, folderName: item.folderName, title: item.title,
            type: item.type, status: patchedStatus, created: item.created,
            updated: item.updated, branch: item.branch, labels: item.labels,
            model: item.model, order: patchedOrder, goal: item.goal
        )
        var snapshot = incoming
        snapshot[idx] = .valid(patched)
        return (snapshot, false)
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

    private func makeOptimisticUpdate(
        issue: Issue, newStatus: IssueStatus, newOrder: SetValue<Double?>
    ) -> DiscoveredIssue {
        let updatedOrder: Double?
        switch newOrder {
        case .keep: updatedOrder = issue.order
        case .set(let value): updatedOrder = value
        }
        return .valid(
            Issue(
                id: issue.id, folderName: issue.folderName, title: issue.title,
                type: issue.type, status: newStatus, created: issue.created,
                updated: Date(), branch: issue.branch, labels: issue.labels,
                model: issue.model, order: updatedOrder, goal: issue.goal
            )
        )
    }

    nonisolated private static func replace(
        _ items: [DiscoveredIssue], folderName: String, with new: DiscoveredIssue
    ) -> [DiscoveredIssue] {
        items.map { $0.id == folderName ? new : $0 }
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
