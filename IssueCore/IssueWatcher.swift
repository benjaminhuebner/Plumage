import Foundation

nonisolated final class IssueWatcher: Sendable {
    nonisolated let events: AsyncStream<IssueChangeEvent>

    convenience init(
        projectURL: URL,
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250)
    ) {
        let source = FSEventSource(
            directory: projectURL.appending(path: ".claude/issues")
        )
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        source.onChange = { rawCont.yield(()) }
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

        continuation.onTermination = { @Sendable _ in
            signaler.cancel()
            pump.cancel()
            onTeardown()
            Task { await debouncer.finish() }
        }
    }
}
