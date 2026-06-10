import Foundation

actor IssueSnapshotProducer {
    nonisolated let snapshots: AsyncStream<[DiscoveredIssue]>
    private let continuation: AsyncStream<[DiscoveredIssue]>.Continuation
    private let projectURL: URL
    private let discover: @Sendable (URL) -> [DiscoveredIssue]
    private let watcher: IssueWatcher
    private var lastSnapshot: [DiscoveredIssue]?
    private var pumpTask: Task<Void, Never>?
    private var hasStarted = false
    private(set) var hasStopped: Bool = false

    init(
        projectURL: URL,
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250),
        discover: @escaping @Sendable (URL) -> [DiscoveredIssue] =
            IssueDiscovery.discoverIssues(in:)
    ) {
        self.init(
            projectURL: projectURL,
            watcher: IssueWatcher(projectURL: projectURL, clock: clock, window: window),
            discover: discover
        )
    }

    init(
        projectURL: URL,
        watcher: IssueWatcher,
        discover: @escaping @Sendable (URL) -> [DiscoveredIssue] =
            IssueDiscovery.discoverIssues(in:)
    ) {
        let (stream, cont) = AsyncStream<[DiscoveredIssue]>.makeStream()
        self.snapshots = stream
        self.continuation = cont
        self.projectURL = projectURL
        self.discover = discover
        self.watcher = watcher
    }

    func start() async {
        // hasStarted (not pumpTask) gates re-entry: the detached await below
        // suspends before pumpTask is assigned, so a second start() racing in
        // could otherwise pass a pumpTask-only guard.
        guard !hasStarted else { return }
        hasStarted = true
        // Detached: discoverIssues does N file reads + YAML decodes — keep
        // that off this actor's executor (and off the caller's).
        let discover = self.discover
        let projectURL = self.projectURL
        let initial = await Task.detached(priority: .userInitiated) {
            discover(projectURL)
        }.value
        lastSnapshot = initial
        continuation.yield(initial)

        let watcherEvents = watcher.events
        pumpTask = Task { [weak self] in
            for await _ in watcherEvents {
                guard let self else { return }
                await self.pumpOnce()
            }
        }
    }

    private func pumpOnce() async {
        let discover = self.discover
        let projectURL = self.projectURL
        let next = await Task.detached(priority: .utility) {
            discover(projectURL)
        }.value
        if next != lastSnapshot {
            lastSnapshot = next
            continuation.yield(next)
        }
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        continuation.finish()
        hasStopped = true
    }

    deinit {
        pumpTask?.cancel()
        continuation.finish()
    }
}
