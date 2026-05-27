import Foundation
import Testing

@testable import Plumage

@Suite("RepoStateReader")
struct RepoStateReaderTests {
    @Test("missing .git/ directory yields notARepo")
    func notARepo() {
        let reader = RepoStateReader(
            fileManager: { _ in false },
            readFile: { _ in nil }
        )
        let state = reader.read(repoURL: URL(filePath: "/tmp/nope"))
        #expect(state == .notARepo)
        #expect(state.isGitRepo == false)
        #expect(state.displayLabel == nil)
    }

    @Test("ref-style HEAD yields .branch")
    func branchHead() {
        let reader = RepoStateReader(
            fileManager: { _ in true },
            readFile: { _ in "ref: refs/heads/main\n" }
        )
        let state = reader.read(repoURL: URL(filePath: "/tmp/repo"))
        #expect(state == .branch("main"))
        #expect(state.displayLabel == "main")
    }

    @Test("ref-style HEAD with slashes preserves branch name verbatim")
    func slashBranchHead() {
        let reader = RepoStateReader(
            fileManager: { _ in true },
            readFile: { _ in "ref: refs/heads/issue/00050-git-functionality\n" }
        )
        let state = reader.read(repoURL: URL(filePath: "/tmp/repo"))
        #expect(state.branchName == "issue/00050-git-functionality")
        #expect(state.isDetached == false)
    }

    @Test("bare SHA HEAD yields .detached truncated to 7 chars")
    func detachedHead() {
        let reader = RepoStateReader(
            fileManager: { _ in true },
            readFile: { _ in "abcdef1234567890abcdef1234567890abcdef12\n" }
        )
        let state = reader.read(repoURL: URL(filePath: "/tmp/repo"))
        #expect(state.isDetached)
        #expect(state.detachedSHA == "abcdef1")
        #expect(state.displayLabel == "(detached) abcdef1")
    }

    @Test("missing HEAD file yields notARepo even if .git/ exists")
    func gitDirButNoHead() {
        let reader = RepoStateReader(
            fileManager: { _ in true },
            readFile: { _ in nil }
        )
        let state = reader.read(repoURL: URL(filePath: "/tmp/half-init"))
        #expect(state == .notARepo)
    }
}

@Suite("GitRepoStateWatcher (unit)")
struct GitRepoStateWatcherTests {
    @Test("initial state is yielded immediately, distinct branch switches propagate")
    func initialAndSwitch() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let counter = ReadCounter(states: [.branch("feature/x")])
        let watcher = GitRepoStateWatcher(
            rawSignals: rawSignals,
            initialState: .branch("main"),
            reader: { counter.next() },
            clock: clock
        )
        let collector = StateCollector()

        let consumer = Task { [states = watcher.states] in
            for await state in states { await collector.record(state) }
        }

        // The initial state lands on the stream the moment a consumer is
        // awaiting; we don't need to advance the clock for it.
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }
        let first = await collector.last
        #expect(first == .branch("main"))

        // Trigger one debounced event → reader returns branch("feature/x").
        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 2 }
        let second = await collector.last
        #expect(second == .branch("feature/x"))

        rawCont.finish()
        consumer.cancel()
        _ = await consumer.value
    }

    @Test("duplicate state does not re-emit (equatable de-dup)")
    func dedup() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        // Reader always returns the same state — `.git/index` touches that
        // don't change HEAD should be silent.
        let counter = ReadCounter(states: [.branch("main"), .branch("main")])
        let watcher = GitRepoStateWatcher(
            rawSignals: rawSignals,
            initialState: .branch("main"),
            reader: { counter.next() },
            clock: clock
        )
        let collector = StateCollector()

        let consumer = Task { [states = watcher.states] in
            for await state in states { await collector.record(state) }
        }

        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        rawCont.yield(())
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        // Give the pump a moment to process; if it would emit, this is when.
        try? await Task.sleep(for: .milliseconds(50))

        let count = await collector.count
        #expect(count == 1)  // still just the initial state

        rawCont.finish()
        consumer.cancel()
        _ = await consumer.value
    }

    @Test("burst coalesces into a single emission")
    func burstCoalesces() async throws {
        let clock = ManualClock()
        let (rawSignals, rawCont) = AsyncStream<Void>.makeStream()
        let counter = ReadCounter(states: [.detached(sha: "deadbee")])
        let watcher = GitRepoStateWatcher(
            rawSignals: rawSignals,
            initialState: .branch("main"),
            reader: { counter.next() },
            clock: clock
        )
        let collector = StateCollector()

        let consumer = Task { [states = watcher.states] in
            for await state in states { await collector.record(state) }
        }

        try await waitUntil(timeout: .seconds(2)) { await collector.count == 1 }

        for _ in 0..<5 { rawCont.yield(()) }
        try await clock.waitForWaiterCount(1)
        clock.advance(by: .milliseconds(250))
        try await waitUntil(timeout: .seconds(2)) { await collector.count == 2 }

        clock.advance(by: .milliseconds(500))
        try? await Task.sleep(for: .milliseconds(50))
        let count = await collector.count
        #expect(count == 2)
        let last = await collector.last
        #expect(last == .detached(sha: "deadbee"))

        rawCont.finish()
        consumer.cancel()
        _ = await consumer.value
    }
}

private actor StateCollector {
    private(set) var count: Int = 0
    private(set) var last: RepoState?
    func record(_ state: RepoState) {
        count += 1
        last = state
    }
}

// Returns each state from `states` once, then sticks on the last one.
private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var index: Int = 0
    private let states: [RepoState]

    init(states: [RepoState]) {
        self.states = states
    }

    func next() -> RepoState {
        lock.withLock {
            let value = states[min(index, states.count - 1)]
            index += 1
            return value
        }
    }
}
