import Foundation
import Observation

@MainActor @Observable
final class RunStatusModel {
    struct LiveRun: Equatable, Sendable {
        let checkoutRoot: URL
        let slug: String
        let state: RunState
        let isWorktree: Bool
    }

    private(set) var liveRuns: [String: LiveRun] = [:]
    private(set) var runSnapshots: [RunStateSnapshot] = []
    private(set) var queuedRuns: [QueuedImplementRun] = []
    private(set) var scannedRoots: [URL] = []
    private(set) var revision = 0

    private let scanRunStates: @Sendable ([URL]) -> [RunStateSnapshot]
    private let scanQueue: @Sendable (URL) -> [QueuedImplementRun]
    private let sweep: @Sendable ([RunStateSnapshot]) -> Int
    private let rootsProvider: (@MainActor (URL) -> [URL])?
    private let observerID = UUID()
    private var projectURL: URL?
    private var notifier: RunCompletionNotifier?
    private var refreshTask: Task<Void, Never>?
    private var needsAnotherPass = false

    init(
        scanRunStates: @escaping @Sendable ([URL]) -> [RunStateSnapshot] =
            ImplementRunScanner.runStates(acrossWorktreeRoots:),
        scanQueue: @escaping @Sendable (URL) -> [QueuedImplementRun] =
            ImplementRunScanner.queuedImplementRuns(in:),
        sweep: @escaping @Sendable ([RunStateSnapshot]) -> Int = {
            CrashedRunSweeper.sweep(snapshots: $0)
        },
        rootsProvider: (@MainActor (URL) -> [URL])? = nil
    ) {
        self.scanRunStates = scanRunStates
        self.scanQueue = scanQueue
        self.sweep = sweep
        self.rootsProvider = rootsProvider
    }

    func start(projectURL: URL, notifier: RunCompletionNotifier = .shared) {
        stop()
        self.projectURL = projectURL
        self.notifier = notifier
        notifier.addRunsObserver(root: projectURL, id: observerID) { [weak self] in
            self?.scheduleRefresh()
        }
        scheduleRefresh()
    }

    func stop() {
        if let projectURL { notifier?.removeRunsObserver(root: projectURL, id: observerID) }
        refreshTask?.cancel()
        refreshTask = nil
        notifier = nil
        projectURL = nil
    }

    nonisolated static func resumeAvailable(
        status: IssueStatus, hasLiveRun: Bool, isQueued: Bool
    ) -> Bool {
        status == .inProgress && !hasLiveRun && !isQueued
    }

    func scheduleRefresh() {
        guard projectURL != nil else { return }
        guard refreshTask == nil else {
            needsAnotherPass = true
            return
        }
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    private func runRefreshLoop() async {
        defer { refreshTask = nil }
        repeat {
            needsAnotherPass = false
            await refresh()
        } while needsAnotherPass && !Task.isCancelled
    }

    func refresh() async {
        guard let projectURL else { return }
        let roots =
            rootsProvider?(projectURL)
            ?? notifier?.watchedRoots(forRoot: projectURL)
            ?? [projectURL]
        let scanRunStates = scanRunStates
        let scanQueue = scanQueue
        let sweep = sweep
        let (snapshots, queue) = await Task.detached(priority: .utility) {
            () -> ([RunStateSnapshot], [QueuedImplementRun]) in
            var snapshots = scanRunStates(roots)
            if sweep(snapshots) > 0 {
                snapshots = scanRunStates(roots)
            }
            return (snapshots, scanQueue(projectURL))
        }.value
        guard !Task.isCancelled, self.projectURL == projectURL else { return }
        apply(
            snapshots: snapshots, queue: queue, roots: roots,
            primaryPath: projectURL.standardizedFileURL.path)
    }

    private func apply(
        snapshots: [RunStateSnapshot], queue: [QueuedImplementRun], roots: [URL],
        primaryPath: String
    ) {
        var live: [String: LiveRun] = [:]
        for snapshot in snapshots where snapshot.isAgentAlive {
            live[snapshot.slug] = LiveRun(
                checkoutRoot: snapshot.checkoutRoot,
                slug: snapshot.slug,
                state: snapshot.state,
                isWorktree: snapshot.checkoutRoot.standardizedFileURL.path != primaryPath
            )
        }
        liveRuns = live
        runSnapshots = snapshots
        queuedRuns = queue
        scannedRoots = roots
        revision &+= 1
    }
}
