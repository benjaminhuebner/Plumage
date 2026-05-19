import Foundation

nonisolated final class IssueWatcher: Sendable {
    nonisolated let events: AsyncStream<IssueChangeEvent>

    // Stored so deinit can cancel them. continuation.onTermination already
    // cancels both, but that only fires when the stream itself is released —
    // if a caller creates an IssueWatcher and drops it without consuming
    // `events`, the tasks would otherwise live until the stream eventually
    // deallocates. deinit closes that gap.
    private let signaler: Task<Void, Never>
    private let pump: Task<Void, Never>

    convenience init(
        projectURL: URL,
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250)
    ) {
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let source = FSEventSource(
            directory: IssueLayout.issuesDirectory(in: projectURL),
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
        let (stream, continuation) = AsyncStream<IssueChangeEvent>.makeStream()
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
