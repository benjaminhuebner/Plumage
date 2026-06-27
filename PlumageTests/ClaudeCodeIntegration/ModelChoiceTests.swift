import Foundation
import Testing

@testable import Plumage

@Suite("ModelChoice")
struct ModelChoiceTests {
    static let aliasCases: [(ModelChoice, String)] = [
        (.default, "default"),
        (.fable, "fable"),
        (.opus, "opus"),
        (.sonnet, "sonnet"),
        (.haiku, "haiku"),
    ]

    @Test("cliArg maps every alias case to the right --model flag")
    func cliArgs() {
        #expect(ModelChoice.default.cliArg.isEmpty)
        #expect(ModelChoice.fable.cliArg == ["--model", "fable"])
        #expect(ModelChoice.opus.cliArg == ["--model", "opus"])
        #expect(ModelChoice.sonnet.cliArg == ["--model", "sonnet"])
        #expect(ModelChoice.haiku.cliArg == ["--model", "haiku"])
    }

    @Test("cliArg passes a custom model name through verbatim")
    func cliArgCustom() {
        #expect(
            ModelChoice.custom("claude-opus-4-6[1m]").cliArg == ["--model", "claude-opus-4-6[1m]"]
        )
    }

    @Test("storageValue matches claude CLI aliases", arguments: aliasCases)
    func storageValueAliases(choice: ModelChoice, storage: String) {
        #expect(choice.storageValue == storage)
        #expect(ModelChoice(storageValue: storage) == choice)
    }

    @Test("Codable round-trips every alias case via JSON", arguments: aliasCases.map(\.0))
    func roundTrip(choice: ModelChoice) throws {
        let data = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == choice)
    }

    @Test("Codable round-trips a custom model name as the bare string")
    func roundTripCustom() throws {
        let choice = ModelChoice.custom("claude-sonnet-4-5-20250929")
        let data = try JSONEncoder().encode(choice)
        #expect(String(data: data, encoding: .utf8) == "\"claude-sonnet-4-5-20250929\"")
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == choice)
    }

    @Test("unknown non-empty string decodes as .custom, not .default")
    func unknownDecodesToCustom() throws {
        let data = try #require("\"sonnet-4-7-future\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == .custom("sonnet-4-7-future"))
    }

    @Test("empty string decodes to .default")
    func emptyDecodesToDefault() throws {
        let data = try #require("\"\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == .default)
    }

    @Test("dropped opusplan alias migrates to .opus")
    func droppedOpusPlanMigratesToOpus() throws {
        let data = try #require("\"opusplan\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == .opus)
        #expect(ModelChoice(storageValue: "opusplan") == .opus)
    }

    @Test("displayName shows the custom value itself")
    func displayNames() {
        #expect(ModelChoice.default.displayName == "Default")
        #expect(ModelChoice.fable.displayName == "Fable")
        #expect(ModelChoice.custom("claude-x").displayName == "claude-x")
    }

    @Test("supportedEfforts varies by model")
    func supportedEfforts() {
        let all: [EffortLevel] = [.default, .low, .medium, .high, .xhigh, .max, .ultracode]
        #expect(ModelChoice.opus.supportedEfforts == all)
        #expect(ModelChoice.fable.supportedEfforts == all)
        #expect(ModelChoice.default.supportedEfforts == all)
        #expect(ModelChoice.custom("anything").supportedEfforts == all)
        #expect(ModelChoice.opus.supportedEfforts.last == .ultracode)
        #expect(ModelChoice.sonnet.supportedEfforts == [.default, .low, .medium, .high, .max])
        #expect(!ModelChoice.sonnet.supportedEfforts.contains(.xhigh))
        #expect(!ModelChoice.sonnet.supportedEfforts.contains(.ultracode))
        #expect(!ModelChoice.haiku.supportedEfforts.contains(.ultracode))
        #expect(ModelChoice.haiku.supportedEfforts == [.default])
    }
}
