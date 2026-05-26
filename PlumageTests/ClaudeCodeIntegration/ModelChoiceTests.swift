import Foundation
import Testing

@testable import Plumage

@Suite("ModelChoice")
struct ModelChoiceTests {
    @Test("cliArg maps every case to the right --model alias")
    func cliArgs() {
        #expect(ModelChoice.default.cliArg.isEmpty)
        #expect(ModelChoice.opus.cliArg == ["--model", "opus"])
        #expect(ModelChoice.sonnet.cliArg == ["--model", "sonnet"])
        #expect(ModelChoice.haiku.cliArg == ["--model", "haiku"])
        #expect(ModelChoice.opusPlan.cliArg == ["--model", "opusplan"])
    }

    @Test("allCases covers the five spec'd options")
    func allCasesCount() {
        #expect(ModelChoice.allCases.count == 5)
        #expect(Set(ModelChoice.allCases) == [.default, .opus, .sonnet, .haiku, .opusPlan])
    }

    @Test("Codable round-trips every case via JSON")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for choice in ModelChoice.allCases {
            let data = try encoder.encode(choice)
            let decoded = try decoder.decode(ModelChoice.self, from: data)
            #expect(decoded == choice)
        }
    }

    @Test("rawValues match claude CLI aliases")
    func rawValueAliases() {
        #expect(ModelChoice.default.rawValue == "default")
        #expect(ModelChoice.opus.rawValue == "opus")
        #expect(ModelChoice.sonnet.rawValue == "sonnet")
        #expect(ModelChoice.haiku.rawValue == "haiku")
        #expect(ModelChoice.opusPlan.rawValue == "opusplan")
    }

    @Test("unknown raw value decodes to .default")
    func unknownDecodesToDefault() throws {
        let data = try #require("\"sonnet-4-7-future\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(ModelChoice.self, from: data)
        #expect(decoded == .default)
    }
}
