import Foundation
import Testing

@testable import Plumage

@Suite("ScaffoldToggles")
struct ScaffoldTogglesTests {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "Toggles-\(UUID().uuidString).json")
    }

    @Test("Missing entry is enabled (subtractive mask default)")
    func missingIsEnabled() {
        let toggles = ScaffoldToggles()
        #expect(toggles.isEnabled(.hooks, "format-swift"))
        #expect(toggles.isEnabled(.skills, "plumage-plan"))
        #expect(toggles.isEnabled(.agents, "anything"))
    }

    @Test("Explicit false disables; explicit true enables")
    func explicitValues() {
        var toggles = ScaffoldToggles()
        toggles.setEnabled(.hooks, "format-swift", false)
        toggles.setEnabled(.hooks, "lint-swift", true)
        #expect(!toggles.isEnabled(.hooks, "format-swift"))
        #expect(toggles.isEnabled(.hooks, "lint-swift"))
        // A different category is unaffected.
        #expect(toggles.isEnabled(.skills, "format-swift"))
    }

    @Test("enabledNames filters disabled and preserves order")
    func enabledNamesFilters() {
        var toggles = ScaffoldToggles()
        toggles.setEnabled(.hooks, "b", false)
        let result = toggles.enabledNames(in: .hooks, from: ["a", "b", "c"])
        #expect(result == ["a", "c"])
    }

    @Test("Round-trips through disk; load of an absent file is empty/all-on")
    func roundTrip() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Absent file → all-on default.
        #expect(try ScaffoldToggles.load(from: url) == ScaffoldToggles())

        var toggles = ScaffoldToggles()
        toggles.setEnabled(.hooks, "format-swift", false)
        toggles.setEnabled(.agents, "reviewer", true)
        try toggles.save(to: url)

        let loaded = try ScaffoldToggles.load(from: url)
        #expect(loaded == toggles)
        #expect(!loaded.isEnabled(.hooks, "format-swift"))
        #expect(loaded.isEnabled(.agents, "reviewer"))
    }

    @Test("Persisted JSON is flat [category: [name: Bool]]")
    func flatJSON() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var toggles = ScaffoldToggles()
        toggles.setEnabled(.hooks, "format-swift", false)
        try toggles.save(to: url)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let hooks = try #require(object?["hooks"] as? [String: Any])
        #expect(hooks["format-swift"] as? Bool == false)
    }

    @Test("Malformed file throws rather than silently defaulting")
    func malformedThrows() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) {
            _ = try ScaffoldToggles.load(from: url)
        }
    }
}
