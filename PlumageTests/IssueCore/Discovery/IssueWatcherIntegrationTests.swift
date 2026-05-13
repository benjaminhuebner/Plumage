import Foundation
import Testing

@testable import Plumage

@Suite("IssueWatcher (integration)")
struct IssueWatcherIntegrationTests {
    @Test("modifying spec.md emits at least one changed event")
    func specEditEmitsEvent() async throws {
        let fixture = try WatcherFixture()
        defer { fixture.cleanup() }
        try fixture.writeSpec(folder: "00001-foo", body: "title: original\n")

        let watcher = IssueWatcher(projectURL: fixture.root)
        let collector = ChangeCollector()

        let consumer = Task { [events = watcher.events] in
            for await event in events { await collector.record(event) }
        }

        // Give the FSEvent stream a moment to install.
        try await Task.sleep(for: .milliseconds(100))

        try fixture.writeSpec(folder: "00001-foo", body: "title: edited\n")
        try await waitUntil(timeout: .seconds(2)) { await collector.count >= 1 }

        let final = await collector.count
        #expect(final >= 1)

        consumer.cancel()
        _ = await consumer.value
        // Allow the continuation's onTermination to drain (FSEvent stop +
        // dispatch queue flush) before the deferred cleanup deletes the dir.
        try? await Task.sleep(for: .milliseconds(50))
    }
}

private struct WatcherFixture {
    let root: URL

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlumageWatcherTest-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appending(path: ".claude/issues"),
            withIntermediateDirectories: true
        )
        self.root = dir
    }

    func writeSpec(folder: String, body: String) throws {
        let folderURL = root.appending(path: ".claude/issues/\(folder)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let specURL = folderURL.appending(path: "spec.md")
        try body.write(to: specURL, atomically: true, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor ChangeCollector {
    private(set) var count: Int = 0
    func record(_: IssueChangeEvent) { count += 1 }
}
