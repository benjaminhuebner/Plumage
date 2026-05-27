import Foundation

// Sibling to GitRepoWatcher (#00041): instead of an opaque `.changed` ping,
// this emits the live RepoState (isGitRepo, branchName, detached SHA) for the
// status-bar indicator. Reads `.git/HEAD` directly via RepoStateReader rather
// than spawning git — cheaper, fewer subprocess slots, and HEAD is the only
// thing we need to look at.
//
// Per #00041 (decisions 2026-05-25): keeping copies of the FSEventSource +
// Debouncer pipeline alongside IssueWatcher and GitRepoWatcher. Rule-of-three
// still in force, fourth caller would trigger the extract.
nonisolated final class GitRepoStateWatcher: Sendable {
    nonisolated let states: AsyncStream<RepoState>

    private let signaler: Task<Void, Never>
    private let pump: Task<Void, Never>
    private let teardown: @Sendable () -> Void

    convenience init(
        repoURL: URL,
        reader: RepoStateReader = RepoStateReader(),
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250)
    ) {
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        // Watch `.git/` recursively — captures HEAD changes (branch switch,
        // detached checkout) as well as index updates. For the indicator we
        // only care about HEAD, but a touch on `.git/index` is a cheap-extra
        // wake-up that just re-reads HEAD and emits the same state (the
        // Equatable de-dup below filters the noise).
        let source = FSEventSource(
            directory: repoURL.appendingPathComponent(".git", isDirectory: true),
            onChange: { rawCont.yield(()) }
        )
        source.start()

        self.init(
            rawSignals: rawSignals,
            initialState: reader.read(repoURL: repoURL),
            reader: { reader.read(repoURL: repoURL) },
            debouncer: Debouncer(window: window, clock: clock),
            onTeardown: {
                rawCont.finish()
                source.stop()
            }
        )
    }

    // Test-only path that bypasses FSEvents and lets the test inject raw
    // signals + a stub reader. `initialState` is the first value pushed onto
    // the stream so consumers see the current state immediately on `await`.
    convenience init<C: Clock>(
        rawSignals: AsyncStream<Void>,
        initialState: RepoState,
        reader: @escaping @Sendable () -> RepoState,
        clock: C,
        window: Duration = .milliseconds(250)
    ) where C.Duration == Duration {
        self.init(
            rawSignals: rawSignals,
            initialState: initialState,
            reader: reader,
            debouncer: Debouncer(window: window, clock: clock),
            onTeardown: {}
        )
    }

    private init<C: Clock>(
        rawSignals: AsyncStream<Void>,
        initialState: RepoState,
        reader: @escaping @Sendable () -> RepoState,
        debouncer: Debouncer<C>,
        onTeardown: @escaping @Sendable () -> Void
    ) where C.Duration == Duration {
        self.teardown = onTeardown

        let (stream, continuation) = AsyncStream<RepoState>.makeStream()
        self.states = stream

        // Push the initial state synchronously so the consumer sees the
        // current branch the moment it starts awaiting `states` — without
        // this, the indicator stays empty until the first FSEvent fires.
        continuation.yield(initialState)

        let signaler = Task {
            for await _ in rawSignals {
                await debouncer.signal()
            }
        }

        let pump = Task { [debouncerEvents = debouncer.events] in
            var last = initialState
            for await _ in debouncerEvents {
                let next = reader()
                // Equatable filter: don't spam consumers with redundant
                // states. An `.git/index` touch yields the same HEAD; that
                // shouldn't tick the indicator.
                if next != last {
                    continuation.yield(next)
                    last = next
                }
            }
        }

        self.signaler = signaler
        self.pump = pump

        continuation.onTermination = { @Sendable _ in
            signaler.cancel()
            pump.cancel()
            onTeardown()
        }
    }

    deinit {
        signaler.cancel()
        pump.cancel()
        teardown()
    }
}
