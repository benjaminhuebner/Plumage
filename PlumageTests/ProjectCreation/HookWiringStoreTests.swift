import Foundation
import Testing

@testable import Plumage

@Suite("HookWiringStore")
struct HookWiringStoreTests {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "HookWirings-\(UUID().uuidString).json")
    }

    @Test("An empty matcher is normalised to nil")
    func emptyMatcherNormalised() {
        #expect(HookWiring(name: "h", event: .stop, matcher: "").matcher == nil)
        #expect(HookWiring(name: "h", event: .stop, matcher: "  ").matcher == nil)
        #expect(HookWiring(name: "h", event: .preToolUse, matcher: "Edit|Write").matcher == "Edit|Write")
    }

    @Test("supportsMatcher only for the tool-use events")
    func supportsMatcher() {
        #expect(HookEvent.preToolUse.supportsMatcher)
        #expect(HookEvent.postToolUse.supportsMatcher)
        #expect(!HookEvent.userPromptSubmit.supportsMatcher)
        #expect(!HookEvent.stop.supportsMatcher)
        #expect(!HookEvent.sessionStart.supportsMatcher)
    }

    @Test("Round-trips through save and load")
    func roundTrip() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HookWiringStore(wirings: [
            HookWiring(name: "guard-foo", event: .preToolUse, matcher: "Bash"),
            HookWiring(name: "announce", event: .sessionStart),
        ])
        try store.save(to: url)
        let loaded = try HookWiringStore.load(from: url)
        #expect(loaded == store)
        #expect(loaded.wiring(named: "announce")?.matcher == nil)
    }

    @Test("Loading an absent file yields an empty store")
    func absentFileEmpty() throws {
        let loaded = try HookWiringStore.load(from: tmpURL())
        #expect(loaded.wirings.isEmpty)
    }

    @Test("Loading a malformed file throws")
    func malformedThrows() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { _ = try HookWiringStore.load(from: url) }
    }

    @Test("upsert inserts then replaces by name")
    func upsertReplaces() {
        var store = HookWiringStore()
        store.upsert(HookWiring(name: "h", event: .stop))
        store.upsert(HookWiring(name: "h", event: .preToolUse, matcher: "Edit"))
        #expect(store.wirings.count == 1)
        #expect(store.wiring(named: "h")?.event == .preToolUse)
        #expect(store.wiring(named: "h")?.matcher == "Edit")
    }

    @Test("remove drops the named wiring")
    func removeDrops() {
        var store = HookWiringStore(wirings: [
            HookWiring(name: "a", event: .stop), HookWiring(name: "b", event: .stop),
        ])
        store.remove(named: "a")
        #expect(store.wirings.map(\.name) == ["b"])
    }
}
