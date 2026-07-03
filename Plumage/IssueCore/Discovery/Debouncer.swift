actor Debouncer<C: Clock> where C.Duration == Duration {
    private let window: Duration
    private let clock: C
    private let continuation: AsyncStream<Void>.Continuation
    nonisolated let events: AsyncStream<Void>
    private var pendingTask: Task<Void, Never>?

    init(window: Duration, clock: C) {
        self.window = window
        self.clock = clock
        let (stream, cont) = AsyncStream<Void>.makeStream()
        self.events = stream
        self.continuation = cont
    }

    func signal() {
        pendingTask?.cancel()
        let window = self.window
        let clock = self.clock
        let continuation = self.continuation
        pendingTask = Task {
            do {
                try await clock.sleep(for: window)
            } catch {
                return
            }
            continuation.yield(())
        }
    }

    func finish() {
        pendingTask?.cancel()
        pendingTask = nil
        continuation.finish()
    }
}
