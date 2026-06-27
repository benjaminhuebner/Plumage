import Foundation
import Testing

@testable import Plumage

private let effortLevelCases: [(EffortLevel, String)] = [
    (.default, "default"),
    (.low, "low"),
    (.medium, "medium"),
    (.high, "high"),
    (.xhigh, "xhigh"),
    (.max, "max"),
    (.ultracode, "ultracode"),
]

@Suite("EffortLevel")
struct EffortLevelTests {
    @Test("cliArg adds --effort for every level except default and ultracode")
    func cliArgs() {
        #expect(EffortLevel.default.cliArg.isEmpty)
        #expect(EffortLevel.low.cliArg == ["--effort", "low"])
        #expect(EffortLevel.medium.cliArg == ["--effort", "medium"])
        #expect(EffortLevel.high.cliArg == ["--effort", "high"])
        #expect(EffortLevel.xhigh.cliArg == ["--effort", "xhigh"])
        #expect(EffortLevel.max.cliArg == ["--effort", "max"])
        #expect(EffortLevel.ultracode.cliArg.isEmpty)
    }

    @Test("settingsOverrides carries ultracode only for the ultracode level")
    func settingsOverrides() {
        #expect(EffortLevel.ultracode.settingsOverrides == ["ultracode": true])
        for level in [EffortLevel.default, .low, .medium, .high, .xhigh, .max] {
            #expect(level.settingsOverrides.isEmpty)
        }
    }

    @Test("settingsCLIArgs is a standalone --settings only for ultracode")
    func settingsCLIArgs() {
        #expect(EffortLevel.ultracode.settingsCLIArgs == ["--settings", #"{"ultracode":true}"#])
        for level in [EffortLevel.default, .low, .medium, .high, .xhigh, .max] {
            #expect(level.settingsCLIArgs.isEmpty)
        }
    }

    @Test("storageValue matches the claude CLI levels", arguments: effortLevelCases)
    func storageValues(level: EffortLevel, storage: String) {
        #expect(level.storageValue == storage)
        #expect(EffortLevel(storageValue: storage) == level)
    }

    @Test("Codable round-trips every level via JSON", arguments: effortLevelCases.map(\.0))
    func roundTrip(level: EffortLevel) throws {
        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(EffortLevel.self, from: data)
        #expect(decoded == level)
    }

    @Test("a level encodes as the bare storage string")
    func encodesBareString() throws {
        let data = try JSONEncoder().encode(EffortLevel.high)
        #expect(String(data: data, encoding: .utf8) == "\"high\"")
    }

    @Test("an unknown or removed level decodes to default")
    func unknownDecodesToDefault() throws {
        let data = try #require("\"ultra\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(EffortLevel.self, from: data)
        #expect(decoded == .default)
        #expect(EffortLevel(storageValue: "ultra") == .default)
    }

    @Test("empty string decodes to default")
    func emptyDecodesToDefault() throws {
        let data = try #require("\"\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(EffortLevel.self, from: data)
        #expect(decoded == .default)
    }

    @Test("displayName is user-facing")
    func displayNames() {
        #expect(EffortLevel.default.displayName == "Default")
        #expect(EffortLevel.xhigh.displayName == "Extra High")
        #expect(EffortLevel.max.displayName == "Max")
        #expect(EffortLevel.ultracode.displayName == "Ultracode")
    }
}
