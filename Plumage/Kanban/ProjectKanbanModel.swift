import Foundation
import Observation
import os

// Intentionally no `import SwiftUI` — pure-Foundation keeps the model testable
// from any host; the animation decision (which mutations animate, which snap)
// lives at the call site in KanbanColumnView / KanbanView via `.animation(_:value:)`.

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

    // Self-documenting pending-drop snapshot — replaces a tuple whose
    // double-Optional order was ambiguous: `.none` and `.some(.keep)` both
    // meant "no order change", but only one was reachable per call site.
    nonisolated struct PendingDrop: Equatable, Sendable {
        let folderName: String
        let expectedStatus: IssueStatus?
        let expectedOrder: SetValue<Double?>
    }

    // Archive/trash wait for a confirmation dialog before they run — both
    // remove the card instantly (and archive has no restore UI), so an
    // unconfirmed context-menu click must not destroy state.
    nonisolated struct PendingRemoval: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case archive
            case trash
        }
        let kind: Kind
        let folderName: String
    }

    typealias Mutator = @Sendable (URL, IssueStatus?, SetValue<Double?>, Date) throws -> Void
    typealias Archiver = @Sendable (_ folderURL: URL, _ archiveRoot: URL) throws -> URL
    typealias Trasher = @Sendable (_ folderURL: URL) throws -> URL

    private(set) var issues: [DiscoveredIssue] = []
    private(set) var groupedIssues: [IssueColumn: [DiscoveredIssue]] = [:]
    private(set) var highlightedIssueID: String?
    private(set) var lastDropError: String?
    private(set) var lastRemovalError: String?
    // Latest folderName whose removal (archive or trash) just completed. Open
    // detail/editor views watch this to auto-pop when their own card disappeared.
    // Set on every success — folder names are unique, so onChange fires reliably.
    private(set) var lastRemovalCompleted: String?
    // Latest folderName whose merge-to-main just completed. Open detail views
    // watch this to auto-pop when their own card got merged. Same observation
    // discipline as lastRemovalCompleted — set on every success, folder names are unique.
    private(set) var lastMergeCompleted: String?
    private(set) var pendingDrop: PendingDrop?
    private(set) var pendingRemoval: PendingRemoval?
    // Non-nil when the issues directory itself is missing — distinguishes a
    // broken project from a legitimately empty board.
    private(set) var boardError: String?

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
    private var topOrderWriteTask: Task<Void, Never>?
    // While inactive, coalesce snapshots to the latest and apply once on
    // reactivation — a background run must not re-render the board per flip.
    private var isActive = true
    private var pendingSnapshot: [DiscoveredIssue]?
    private var runProjectURL: URL?

    private nonisolated static let logger = Logger(
        subsystem: "com.plumage", category: "ProjectKanbanModel")

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

    // Safety net for teardown: `[weak self]` in the Task closures prevents retain
    // cycles, not running tasks against a dropped model. isolated deinit
    // (Swift 6.2) so we can touch MainActor state.
    isolated deinit {
        highlightTask?.cancel()
        dropTask?.cancel()
        removalTask?.cancel()
        errorClearTask?.cancel()
        topOrderWriteTask?.cancel()
    }

    func run(projectURL: URL) async {
        refreshBoardError(projectURL: projectURL)
        let producer = producerFactory(projectURL)
        await producer.start()
        for await snapshot in producer.snapshots {
            ingest(snapshot, projectURL: projectURL)
        }
        await producer.stop()
    }

    func ingest(_ snapshot: [DiscoveredIssue], projectURL: URL) {
        runProjectURL = projectURL
        if isActive {
            applySnapshot(snapshot, projectURL: projectURL)
        } else {
            pendingSnapshot = snapshot
        }
    }

    func setActive(_ active: Bool) {
        let wasActive = isActive
        isActive = active
        guard active, !wasActive, let snapshot = pendingSnapshot, let url = runProjectURL else {
            return
        }
        pendingSnapshot = nil
        applySnapshot(snapshot, projectURL: url)
    }

    private func applySnapshot(_ snapshot: [DiscoveredIssue], projectURL: URL) {
        let reconciled = Self.reconcile(incoming: snapshot, pending: pendingDrop)
        let entryOrders = Self.columnEntryOrders(previous: issues, incoming: reconciled.snapshot)
        let groups = Self.group(reconciled.snapshot)
        // `@Observable` re-renders on every set; skip identical snapshots so a
        // content-only spec edit doesn't redraw the whole board.
        if reconciled.snapshot != issues {
            self.issues = reconciled.snapshot
            self.groupedIssues = groups
        }
        if reconciled.pendingCleared {
            pendingDrop = nil
        }
        // A non-empty board proves the issues dir exists; only stat when empty.
        if reconciled.snapshot.isEmpty {
            refreshBoardError(projectURL: projectURL)
        } else if boardError != nil {
            boardError = nil
        }
        scheduleTopOrderWrites(entryOrders, projectURL: projectURL)
    }

    private func scheduleTopOrderWrites(
        _ writes: [(folderName: String, order: Double)], projectURL: URL
    ) {
        guard !writes.isEmpty else { return }
        let mutatorFn = mutator
        let targets = writes.map {
            (IssueLayout.specURL(in: projectURL, folderName: $0.folderName), $0.order)
        }
        // Intentionally not cancelling a prior write task: each batch belongs
        // to its own snapshot and must complete. The slot only enables the
        // deinit cancel.
        topOrderWriteTask = Task.detached {
            for (specURL, order) in targets {
                do {
                    try mutatorFn(specURL, nil, .set(order), Date())
                } catch {
                    Self.logger.error(
                        "Top-order write failed for \(specURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    // One stat call per (debounced) snapshot: an empty array from a missing
    // issues directory must read as an error, not as an empty board.
    private func refreshBoardError(projectURL: URL) {
        let issuesDir = IssueLayout.issuesDirectory(in: projectURL)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: issuesDir.path, isDirectory: &isDirectory)
        let newError =
            (exists && isDirectory.boolValue)
            ? nil
            : "Issues folder missing: .claude/issues — the board can't load."
        if newError != boardError { boardError = newError }
    }

    func requestArchive(folderName: String) {
        pendingRemoval = PendingRemoval(kind: .archive, folderName: folderName)
    }

    func requestTrash(folderName: String) {
        pendingRemoval = PendingRemoval(kind: .trash, folderName: folderName)
    }

    func cancelPendingRemoval() {
        pendingRemoval = nil
    }

    func confirmRemoval(_ removal: PendingRemoval, projectURL: URL) {
        pendingRemoval = nil
        switch removal.kind {
        case .archive:
            applyOptimisticArchive(folderName: removal.folderName, projectURL: projectURL)
        case .trash:
            applyOptimisticTrash(folderName: removal.folderName, projectURL: projectURL)
        }
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

    func clearRemovalError() {
        lastRemovalError = nil
    }

    // Cross-model signal fired by IssueDetailView after a successful merge; detail
    // views dismiss via .onChange when the value matches their folderName. Pattern
    // duplicated from lastRemovalCompleted — generalizing would obscure which completion fired.
    func signalMergeCompleted(folderName: String) {
        lastMergeCompleted = folderName
    }

    #if DEBUG
    func _setIssuesForTesting(_ issues: [DiscoveredIssue]) {
        self.issues = issues
        self.groupedIssues = Self.group(issues)
    }
    #endif

    // Cancels any prior in-flight drop and schedules a new one. Views must use
    // this instead of unstructured Tasks in gesture callbacks — rapid drops could
    // otherwise commit to disk out of order relative to the UI snapshot they read.
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

    // Synchronous wrapper: optimistic update on the calling turn, disk write in
    // the background. For callers needing the optimistic state immediately — the
    // source card must be at its new slot the moment the floating overlay clears.
    func applyOptimisticDrop(
        _ payload: IssueDragPayload,
        to target: DropTarget,
        projectURL: URL
    ) {
        guard let issue = lookupValidIssue(payload.folderName) else { return }
        // groupedIssues is already column-filtered and kanban-sorted — no
        // need to re-derive both from the flat snapshot per drop.
        let mutation = Self.computeMutation(
            issue: issue, target: target, grouped: groupedIssues)
        guard case .apply(let newStatus, let newOrder) = mutation else { return }

        let priorIssues = issues
        let updated = makeOptimisticUpdate(
            issue: issue, newStatus: newStatus, newOrder: newOrder)
        pendingDrop = PendingDrop(
            folderName: issue.folderName,
            expectedStatus: newStatus,
            expectedOrder: newOrder
        )
        // WITHOUT withAnimation: animating would grow the collapsed drag source
        // in at the OLD index before sliding it to the new one. The floating
        // overlay was already at the insertion point — snapping appears in place.
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
                // A newer drop cancelling us cascades into Task.detached's await
                // and lands here. Do NOT roll back then — priorIssues is stale
                // relative to the newer drop and would overwrite its newer state.
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
        // resurrect cards archived/trashed while the write was in flight and
        // clobber other cards' newer optimistic state. Mutate-only; the view animates.
        if let priorCard = prior.first(where: { $0.id == folderName }),
            issues.contains(where: { $0.id == folderName })
        {
            issues = Self.replace(issues, folderName: folderName, with: priorCard)
            groupedIssues = Self.group(issues)
        }
        pendingDrop = nil
        surfaceDropError(error)
    }

    // Setting one kind clears the other: the view's ?? chain prefers drop
    // errors, so an older drop error would otherwise mask a fresh removal
    // error for its whole banner lifetime.
    private func surfaceDropError(_ error: String) {
        lastDropError = error
        lastRemovalError = nil
        scheduleErrorAutoClear()
    }

    private func surfaceRemovalError(_ error: String) {
        lastRemovalError = error
        lastDropError = nil
        scheduleErrorAutoClear()
    }

    // Banners clear themselves — a stale error string in the status bar
    // would outlive the situation it describes. Clearing both slots is
    // safe: surface… guarantees at most one is set.
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
                // Same cancellation discipline as applyOptimisticDrop: if a newer
                // removal cancelled us, priorIssues is stale and writing it back
                // would resurrect a card the user already deleted in the second action.
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
        surfaceRemovalError(error)
    }

    // No optimistic patch on column entry: the write's own FSEvent moves the
    // card, so a failed write simply leaves it at the fallback position.
    nonisolated static func columnEntryOrders(
        previous: [DiscoveredIssue],
        incoming: [DiscoveredIssue]
    ) -> [(folderName: String, order: Double)] {
        guard !previous.isEmpty else { return [] }
        var previousColumns: [String: IssueColumn] = [:]
        for item in previous {
            if case .valid(let issue) = item {
                previousColumns[issue.folderName] = issue.column
            }
        }
        var entrantsByColumn: [IssueColumn: [DiscoveredIssue]] = [:]
        for item in incoming {
            guard case .valid(let issue) = item,
                let oldColumn = previousColumns[issue.folderName],
                oldColumn != issue.column
            else { continue }
            entrantsByColumn[issue.column, default: []].append(item)
        }
        guard !entrantsByColumn.isEmpty else { return [] }

        let incomingByColumn = Dictionary(grouping: incoming, by: \.column)
        var writes: [(folderName: String, order: Double)] = []
        for (column, entrants) in entrantsByColumn {
            let entrantIDs = Set(entrants.map(\.id))
            let columnItems = (incomingByColumn[column] ?? [])
                .filter { !entrantIDs.contains($0.id) }
            guard let base = IssueSortKey.topOrder(in: columnItems) else { continue }
            let sortedEntrants = entrants.sortedForKanban()
            // A lone entrant whose explicit order already tops the column got
            // it from its own app-initiated write — skipping stops the re-fire.
            // An ID fallback never suppresses the write.
            if sortedEntrants.count == 1, let only = sortedEntrants.first,
                let explicitOrder = only.orderValue, explicitOrder <= base
            {
                continue
            }
            for (offset, entrant) in sortedEntrants.enumerated() {
                writes.append((entrant.id, base - Double(sortedEntrants.count - 1 - offset)))
            }
        }
        return writes
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
            order: patchedOrder, goal: item.goal
        )
        var snapshot = incoming
        snapshot[idx] = .valid(patched)
        return (snapshot, false)
    }

    // Epsilon, not exact: older builds wrote %g-rounded order values (6 significant
    // digits), so an exact compare left pendingDrop stuck and re-patched stale
    // status on every snapshot. 1e-5 relative matches the %g precision loss.
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
        computeMutation(
            issue: issue,
            target: target,
            grouped: Dictionary(grouping: snapshot, by: \.column)
                .mapValues { $0.sortedForKanban() }
        )
    }

    nonisolated static func computeMutation(
        issue: Issue,
        target: DropTarget,
        grouped: [IssueColumn: [DiscoveredIssue]]
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
                sortedColumnItems: grouped[column] ?? [],
                insertAbove: true
            )

        case .belowCard(let folderName, let column):
            if folderName == issue.folderName { return .noop }
            return reorderMutation(
                issue: issue,
                issueColumn: issueColumn,
                targetFolderName: folderName,
                targetColumn: column,
                sortedColumnItems: grouped[column] ?? [],
                insertAbove: false
            )
        }
    }

    nonisolated private static func reorderMutation(
        issue: Issue,
        issueColumn: IssueColumn,
        targetFolderName: String,
        targetColumn: IssueColumn,
        sortedColumnItems: [DiscoveredIssue],
        insertAbove: Bool
    ) -> DropMutation {
        let columnItems = sortedColumnItems.filter { $0.id != issue.folderName }
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
                order: updatedOrder, goal: issue.goal
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
        // Sort each column by orderValue (idValue fallback) regardless of `issues`
        // ordering: the optimistic update's `Self.replace` keeps the source at its
        // old array position, which rendered the card at the wrong slot until FSEvent re-sorted.
        Dictionary(grouping: issues, by: \.column).mapValues { $0.sortedForKanban() }
    }
}
