import Foundation
import Observation

// Intentionally no `import SwiftUI` — kept pure-Foundation so the model is
// fully testable from any host and the animation decision (which mutations
// animate, which snap) lives at the call site in KanbanColumnView /
// KanbanView via `.animation(_:value:)`.

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

    // Self-documenting pending-drop snapshot. Replaces the previous
    // `(String?, IssueStatus?, SetValue<Double?>?)` triple where the
    // double-Optional on order was ambiguous — `.none` and `.some(.keep)`
    // both meant "no order change", but only one was reachable per call site.
    nonisolated struct PendingDrop: Equatable, Sendable {
        let folderName: String
        let expectedStatus: IssueStatus?
        let expectedOrder: SetValue<Double?>
    }

    typealias Mutator = @Sendable (URL, IssueStatus?, SetValue<Double?>, Date) throws -> Void
    typealias Archiver = @Sendable (_ folderURL: URL, _ archiveRoot: URL) throws -> URL
    typealias Trasher = @Sendable (_ folderURL: URL) throws -> URL

    private(set) var issues: [DiscoveredIssue] = []
    private(set) var groupedIssues: [IssueColumn: [DiscoveredIssue]] = [:]
    private(set) var highlightedIssueID: String?
    private(set) var lastDropError: String?
    private(set) var lastRemovalError: String?
    // Latest folderName whose removal (archive or trash) just completed
    // successfully. Open detail/editor views watch this to auto-pop when
    // their own card is the one that disappeared. Setting it on every
    // success even if the same folder name comes back lets onChange-based
    // observers fire reliably (Swift Testing equality short-circuits, but
    // we always set the field to a distinct value: folder names are unique).
    private(set) var lastRemovalCompleted: String?
    // Latest folderName whose merge-to-main just completed successfully. Open
    // detail views watch this to auto-pop when their own card is the one that
    // got merged. Same observation discipline as lastRemovalCompleted — the
    // signal is fired even when the same folder name comes back, because
    // folder names are unique per project so a repeated set always represents
    // a distinct event.
    private(set) var lastMergeCompleted: String?
    private(set) var pendingDrop: PendingDrop?

    var pendingDropFolderName: String? { pendingDrop?.folderName }
    var pendingDropExpectedStatus: IssueStatus? { pendingDrop?.expectedStatus }
    var pendingDropExpectedOrder: SetValue<Double?>? { pendingDrop?.expectedOrder }

    private let producerFactory: @Sendable (URL) -> IssueSnapshotProducer
    private let highlightClock: any Clock<Duration>
    private let highlightDuration: Duration
    private let mutator: Mutator
    private let archiver: Archiver
    private let trasher: Trasher
    private var highlightTask: Task<Void, Never>?
    private var dropTask: Task<Void, Never>?
    private var removalTask: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?

    init(
        producerFactory: @escaping @Sendable (URL) -> IssueSnapshotProducer = {
            IssueSnapshotProducer(projectURL: $0)
        },
        clock: any Clock<Duration> = ContinuousClock(),
        highlightDuration: Duration = .seconds(1),
        mutator: @escaping Mutator = { url, status, order, now in
            try FrontmatterMutator.mutate(
                specURL: url, newStatus: status, newOrder: order, now: now)
        },
        archiver: @escaping Archiver = { folderURL, archiveRoot in
            try IssueArchiver.archive(folderURL: folderURL, archiveRoot: archiveRoot)
        },
        trasher: @escaping Trasher = { folderURL in
            try IssueArchiver.trash(folderURL: folderURL)
        }
    ) {
        self.producerFactory = producerFactory
        self.highlightClock = clock
        self.highlightDuration = highlightDuration
        self.mutator = mutator
        self.archiver = archiver
        self.trasher = trasher
    }

    // Safety net for teardown paths. Models are scene-scoped today so this
    // rarely fires, but mirrors IssueDetailModel's discipline — `[weak self]`
    // in the Task closures prevents retain cycles, not running tasks against a
    // dropped model. isolated deinit (Swift 6.2) so we can touch MainActor state.
    isolated deinit {
        highlightTask?.cancel()
        dropTask?.cancel()
        removalTask?.cancel()
        errorClearTask?.cancel()
    }

    func run(projectURL: URL) async {
        let producer = producerFactory(projectURL)
        await producer.start()
        for await snapshot in producer.snapshots {
            let reconciled = Self.reconcile(incoming: snapshot, pending: pendingDrop)
            let groups = Self.group(reconciled.snapshot)
            // Mutate-only: KanbanColumnView attaches `.animation(.smooth, value:)`
            // for the FSEvent path. The pending-drop clear and the FSEvent
            // re-render both look identical from this side; the view layer
            // decides whether the change animates.
            self.issues = reconciled.snapshot
            self.groupedIssues = groups
            if reconciled.pendingCleared {
                pendingDrop = nil
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

    func clearRemovalError() {
        lastRemovalError = nil
    }

    // Cross-model signal fired by IssueDetailView after a successful merge.
    // Detail views observe this via .onChange and dismiss themselves when
    // the value matches their own folderName. Pattern duplicated from
    // lastRemovalCompleted (#00018); generalizing them would obscure which
    // kind of completion fired.
    func signalMergeCompleted(folderName: String) {
        lastMergeCompleted = folderName
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

    // Synchronous wrapper that applies the optimistic update on the calling
    // turn and fires the disk write into the background. Callers that need to
    // observe the optimistic state immediately (the drop gesture: the source
    // card must be at its new slot the moment the floating overlay clears,
    // otherwise the user sees "first below, then plopp") use this entry
    // point. Tests still use the async performDropOptimistic.
    func applyOptimisticDrop(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) {
        guard let issue = lookupValidIssue(payload.folderName) else { return }
        let mutation = Self.computeMutation(
            issue: issue, target: target, snapshot: issues)
        guard case .apply(let newStatus, let newOrder) = mutation else { return }

        let priorIssues = issues
        let updated = makeOptimisticUpdate(
            issue: issue, newStatus: newStatus, newOrder: newOrder)
        pendingDrop = PendingDrop(
            folderName: issue.folderName,
            expectedStatus: newStatus,
            expectedOrder: newOrder
        )
        // Apply the optimistic update WITHOUT withAnimation: the layout
        // transition would otherwise animate the source from its collapsed
        // drag-source state (height 0, opacity 0) at the OLD index to its
        // full natural state at the NEW index — visible to the user as the
        // card "growing in" at the wrong slot before sliding to the right
        // one. The floating overlay was already at the insertion point;
        // letting the layout snap means the source appears in place at the
        // exact spot the overlay just vacated.
        issues = Self.replace(issues, folderName: issue.folderName, with: updated)
        groupedIssues = Self.group(issues)

        let specURL = IssueLayout.specURL(in: projectURL, folderName: issue.folderName)
        let mutatorFn = mutator
        dropTask?.cancel()
        dropTask = Task { [weak self] in
            do {
                try await Task.detached {
                    try mutatorFn(specURL, newStatus, newOrder, Date())
                }.value
            } catch {
                // If the parent Task was cancelled (a newer drop has taken
                // over the dropTask slot), the cancel cascades into
                // Task.detached's await and we land here. Do NOT roll back
                // in that case — priorIssues is stale relative to the
                // newer drop's optimistic update, and writing it back
                // would overwrite the newer state with our old snapshot.
                guard !Task.isCancelled else { return }
                self?.rollbackOptimisticDrop(
                    to: priorIssues, folderName: issue.folderName,
                    error: error.localizedDescription)
            }
        }
    }

    func performDropOptimistic(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) async {
        applyOptimisticDrop(payload, to: target, projectURL: projectURL)
        // Snapshot the task before awaiting — a concurrent dispatchDrop on
        // the next main-actor turn would otherwise replace `dropTask` and
        // we'd accidentally await the wrong work.
        let task = dropTask
        await task?.value
    }

    private func rollbackOptimisticDrop(
        to prior: [DiscoveredIssue], folderName: String, error: String
    ) {
        // Targeted, not whole-array: restoring the full prior snapshot would
        // resurrect cards that were archived/trashed while the drop write was
        // in flight, and clobber other cards' newer optimistic state.
        // Mutate-only; view-side `.animation(.smooth, value: kanban.issues)`
        // handles the visual transition. See `run` for the same reasoning.
        if let priorCard = prior.first(where: { $0.id == folderName }),
            issues.contains(where: { $0.id == folderName })
        {
            issues = Self.replace(issues, folderName: folderName, with: priorCard)
            groupedIssues = Self.group(issues)
        }
        pendingDrop = nil
        lastDropError = error
        scheduleErrorAutoClear()
    }

    // Banner messages clear themselves after a few seconds (NavigatorModel's
    // showBanner discipline) — a stale error string over the status bar would
    // otherwise outlive the situation it describes.
    private func scheduleErrorAutoClear() {
        errorClearTask?.cancel()
        let clock = highlightClock
        errorClearTask = Task { [weak self] in
            try? await clock.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.lastDropError = nil
            self?.lastRemovalError = nil
        }
    }

    func applyOptimisticArchive(folderName: String, projectURL: URL) {
        guard issues.contains(where: { $0.id == folderName }) else { return }
        let priorIssues = issues
        issues = issues.filter { $0.id != folderName }
        groupedIssues = Self.group(issues)
        let folderURL = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
        let archiveRoot = IssueLayout.archiveDirectory(in: projectURL)
        let archiverFn = archiver
        removalTask?.cancel()
        removalTask = Task { [weak self] in
            do {
                _ = try await Task.detached {
                    try archiverFn(folderURL, archiveRoot)
                }.value
                guard !Task.isCancelled else { return }
                self?.lastRemovalCompleted = folderName
            } catch {
                // Same cancellation discipline as applyOptimisticDrop's catch
                // block (notes.md 2026-05-14): if a newer removal cancelled us,
                // priorIssues is stale relative to the newer removal's snapshot
                // and writing it back would resurrect a card that the user
                // already deleted in the second action.
                guard !Task.isCancelled else { return }
                self?.rollbackOptimisticRemoval(
                    to: priorIssues, folderName: folderName,
                    error: error.localizedDescription)
            }
        }
    }

    func performArchiveOptimistic(folderName: String, projectURL: URL) async {
        applyOptimisticArchive(folderName: folderName, projectURL: projectURL)
        let task = removalTask
        await task?.value
    }

    func applyOptimisticTrash(folderName: String, projectURL: URL) {
        guard issues.contains(where: { $0.id == folderName }) else { return }
        let priorIssues = issues
        issues = issues.filter { $0.id != folderName }
        groupedIssues = Self.group(issues)
        let folderURL = IssueLayout.issueFolder(in: projectURL, folderName: folderName)
        let trasherFn = trasher
        removalTask?.cancel()
        removalTask = Task { [weak self] in
            do {
                _ = try await Task.detached {
                    try trasherFn(folderURL)
                }.value
                guard !Task.isCancelled else { return }
                self?.lastRemovalCompleted = folderName
            } catch {
                guard !Task.isCancelled else { return }
                self?.rollbackOptimisticRemoval(
                    to: priorIssues, folderName: folderName,
                    error: error.localizedDescription)
            }
        }
    }

    func performTrashOptimistic(folderName: String, projectURL: URL) async {
        applyOptimisticTrash(folderName: folderName, projectURL: projectURL)
        let task = removalTask
        await task?.value
    }

    // Mirror of rollbackOptimisticDrop for archive/trash. Kept duplicated
    // intentionally — generalizing the two would force callers to share an
    // error surface and obscure which kind of removal failed.
    private func rollbackOptimisticRemoval(
        to prior: [DiscoveredIssue], folderName: String, error: String
    ) {
        // Targeted: only the card whose removal failed comes back; the rest
        // of the prior snapshot may be stale relative to concurrent drops.
        // Append suffices — group() re-sorts per column.
        if let priorCard = prior.first(where: { $0.id == folderName }),
            !issues.contains(where: { $0.id == folderName })
        {
            issues = issues + [priorCard]
            groupedIssues = Self.group(issues)
        }
        lastRemovalError = error
        scheduleErrorAutoClear()
    }

    nonisolated static func reconcile(
        incoming: [DiscoveredIssue],
        pending: PendingDrop?
    ) -> (snapshot: [DiscoveredIssue], pendingCleared: Bool) {
        guard let pending else { return (incoming, false) }
        guard let idx = incoming.firstIndex(where: { $0.id == pending.folderName }) else {
            return (incoming, true)
        }
        guard case .valid(let item) = incoming[idx] else {
            return (incoming, false)
        }
        let statusMatch = pending.expectedStatus == nil || item.status == pending.expectedStatus
        let orderMatch: Bool
        switch pending.expectedOrder {
        case .keep:
            orderMatch = true
        case .set(let expected):
            orderMatch = ordersEqual(item.order, expected)
        }
        if statusMatch && orderMatch {
            return (incoming, true)
        }
        let patchedStatus = pending.expectedStatus ?? item.status
        let patchedOrder: Double?
        switch pending.expectedOrder {
        case .keep:
            patchedOrder = item.order
        case .set(let value):
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

    // Epsilon, not exact: spec files written by older Plumage builds carry
    // %g-rounded order values (6 significant digits), so an exact compare
    // left pendingDrop stuck and re-patched stale status on every snapshot.
    // 1e-5 relative matches the %g precision loss.
    nonisolated private static func ordersEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return abs(left - right) <= max(1e-9, abs(left) * 1e-5)
        default:
            return false
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
        // Sort each column by orderValue (with idValue fallback) so the
        // display always reflects the kanban sort regardless of how the
        // underlying `issues` array is ordered. Without this, the optimistic
        // update's `Self.replace` keeps the source at its old array position
        // — so a card with a new order field renders at its old slot until
        // FSEvent reload re-sorts via discoverIssues. That manifested as
        // "card lands at wrong slot for a few hundred ms, then jumps to
        // the right one when the disk write comes back".
        Dictionary(grouping: issues, by: \.column).mapValues { $0.sortedForKanban() }
    }
}
