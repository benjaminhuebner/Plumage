import Foundation

nonisolated enum SidebarFileChangeEvent: Equatable, Sendable {
    case changed
}

// FSEventSource + Debouncer are duplicated from IssueCore/Discovery by the
// rule-of-three; extraction of a generic watcher waits for a further caller.
nonisolated final class SidebarFileWatcher: Sendable {
    nonisolated let events: AsyncStream<SidebarFileChangeEvent>

    private let signaler: Task<Void, Never>
    private let pump: Task<Void, Never>
    private let teardown: @Sendable () -> Void

    convenience init(
        projectURL: URL,
        clock: some Clock<Duration> = ContinuousClock(),
        window: Duration = .milliseconds(250)
    ) {
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let source = FSEventSource(
            directory: projectURL,
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
        self.teardown = onTeardown

        let (stream, continuation) = AsyncStream<SidebarFileChangeEvent>.makeStream()
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
