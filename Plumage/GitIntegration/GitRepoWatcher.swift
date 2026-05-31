import Foundation

nonisolated enum GitRepoChangeEvent: Equatable, Sendable {
    case changed
}

// FSEventSource + Debouncer are duplicated from IssueCore/Discovery by the
// rule-of-three; a fourth caller would justify extracting a generic watcher.
nonisolated final class GitRepoWatcher: Sendable {
    nonisolated let events: AsyncStream<GitRepoChangeEvent>

    private let signaler: Task<Void, Never>
    private let pump: Task<Void, Never>
    private let teardown: @Sendable () -> Void

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
        // Store teardown so deinit can fire it directly. Without this, the
        // FSEventSource only stops when continuation.onTermination runs,
        // which requires somebody to finish the events stream — nothing in
        // the normal lifecycle does that, so the source would leak per
        // opened card. Both FSEventSource.stop() and the rawCont.finish()
        // it wraps are idempotent, so a double-fire (deinit + onTermination
        // if a consumer also cancels) is safe.
        self.teardown = onTeardown

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
        teardown()
    }
}
