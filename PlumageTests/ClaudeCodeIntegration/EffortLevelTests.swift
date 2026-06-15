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
]

@Suite("EffortLevel")
struct EffortLevelTests {
    @Test("cliArg adds --effort for every level except default")
    func cliArgs() {
        #expect(EffortLevel.default.cliArg.isEmpty)
        #expect(EffortLevel.low.cliArg == ["--effort", "low"])
        #expect(EffortLevel.medium.cliArg == ["--effort", "medium"])
        #expect(EffortLevel.high.cliArg == ["--effort", "high"])
        #expect(EffortLevel.xhigh.cliArg == ["--effort", "xhigh"])
        #expect(EffortLevel.max.cliArg == ["--effort", "max"])
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
    }
}
