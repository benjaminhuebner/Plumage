import Foundation

nonisolated enum GitRepoChangeEvent: Equatable, Sendable {
    case changed
}

// Watches the `.git/` directory of a repo and emits a debounced `.changed`
// event whenever HEAD, index, or the current branch ref changes — enough
// signal to know a commit/checkout/rebase happened without polling.
// FSEventSource is reused from IssueCore/Discovery; per decisions.md
// 2026-05-20 (#00030) and 2026-05-22 (#00036) we keep the copy-by-reuse
// pattern until a fourth caller justifies extracting a generic watcher.
nonisolated final class GitRepoWatcher: Sendable {
    nonisolated let events: AsyncStream<GitRepoChangeEvent>

    private let signaler: Task<Void, Never>
    private let pump: Task<Void, Never>

    convenience init(
        repoURL: URL,
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250)
    ) {
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let source = FSEventSource(
            directory: repoURL.appendingPathComponent(".git", isDirectory: true),
            onChange: { rawCont.yield(()) }
        )
        source.start()

        self.init(
            rawSignals: rawSignals,
            debouncer: Debouncer(window: window, clock: clock),
            onTeardown: {
                rawCont.finish()
                source.stop()
            }
        )
    }

    convenience init<C: Clock>(
        rawSignals: AsyncStream<Void>,
        clock: C,
        window: Duration = .milliseconds(250)
    ) where C.Duration == Duration {
        self.init(
            rawSignals: rawSignals,
            debouncer: Debouncer(window: window, clock: clock),
            onTeardown: {}
        )
    }

    private init<C: Clock>(
        rawSignals: AsyncStream<Void>,
        debouncer: Debouncer<C>,
        onTeardown: @escaping @Sendable () -> Void
    ) where C.Duration == Duration {
        let (stream, continuation) = AsyncStream<GitRepoChangeEvent>.makeStream()
        self.events = stream

        let signaler = Task {
            for await _ in rawSignals {
                await debouncer.signal()
            }
        }

        let pump = Task { [debouncerEvents = debouncer.events] in
            for await _ in debouncerEvents {
                continuation.yield(.changed)
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
    }
}
