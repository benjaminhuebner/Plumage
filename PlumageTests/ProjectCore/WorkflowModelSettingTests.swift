import Foundation
import Testing

@testable import Plumage

@Suite("WorkflowModelSetting string-or-object Codable")
struct WorkflowModelSettingTests {
    private func decode(_ json: String) throws -> WorkflowModelSetting {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(WorkflowModelSetting.self, from: data)
    }

    private func encodeToJSONObject(_ setting: WorkflowModelSetting) throws -> Any {
        let data = try JSONEncoder().encode(setting)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @Test("JSON string decodes to .uniform")
    func stringDecodesUniform() throws {
        #expect(try decode("\"opus\"") == .uniform(.opus))
        #expect(try decode("\"my-custom-model\"") == .uniform(.custom("my-custom-model")))
        #expect(try decode("\"default\"") == .uniform(.default))
    }

    @Test("JSON object decodes to .perType with all four types completed")
    func objectDecodesPerType() throws {
        let setting = try decode(#"{"feature": "opus", "chore": "haiku"}"#)
        #expect(
            setting
                == .perType([
                    .feature: .opus, .chore: .haiku, .spike: .default, .refactor: .default,
                ]))
    }

    @Test("object with identical values collapses to .uniform on decode")
    func identicalObjectCollapses() throws {
        let setting = try decode(
            #"{"feature": "sonnet", "chore": "sonnet", "spike": "sonnet", "refactor": "sonnet"}"#)
        #expect(setting == .uniform(.sonnet))
    }

    @Test("unknown object keys are ignored on decode")
    func unknownKeysIgnored() throws {
        let setting = try decode(#"{"feature": "opus", "epic": "haiku"}"#)
        #expect(setting.choice(for: .feature) == .opus)
        #expect(setting.choice(for: .chore) == .default)
        if case .uniform = setting {
            Testing.Issue.record("expected .perType, got .uniform")
        }
    }

    @Test("empty object decodes as uniform .default")
    func emptyObjectIsUniformDefault() throws {
        #expect(try decode("{}") == .uniform(.default))
    }

    @Test("neither string nor object fails to decode")
    func invalidShapeThrows() {
        #expect(throws: DecodingError.self) {
            try decode("42")
        }
    }

    @Test(".uniform encodes as plain string")
    func uniformEncodesString() throws {
        let value = try encodeToJSONObject(.uniform(.haiku))
        #expect(value as? String == "haiku")
    }

    @Test(".perType with differing values encodes as full four-key object")
    func perTypeEncodesObject() throws {
        let value = try encodeToJSONObject(.perType([.feature: .opus, .chore: .haiku]))
        let dict = try #require(value as? [String: String])
        #expect(
            dict == [
                "feature": "opus", "chore": "haiku", "spike": "default", "refactor": "default",
            ])
    }

    @Test(".perType with identical values encodes as plain string")
    func perTypeCollapsesOnEncode() throws {
        let map = Dictionary(uniqueKeysWithValues: IssueType.allCases.map { ($0, ModelChoice.sonnet) })
        let value = try encodeToJSONObject(.perType(map))
        #expect(value as? String == "sonnet")
    }

    @Test("mixed setting round-trips")
    func mixedRoundTrip() throws {
        let original = WorkflowModelSetting.perType([
            .feature: .opus, .chore: .haiku, .spike: .custom("x-1"), .refactor: .default,
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkflowModelSetting.self, from: data)
        #expect(decoded == original)
    }

    @Test("choice(for:) returns per-type hit, nil for missing, uniform for uniform")
    func choiceLookup() {
        let mixed = WorkflowModelSetting.perType([.feature: .opus])
        #expect(mixed.choice(for: .feature) == .opus)
        #expect(mixed.choice(for: .spike) == nil)
        #expect(WorkflowModelSetting.uniform(.haiku).choice(for: .refactor) == .haiku)
    }

    @Test("normalized completes missing types and collapses identical maps")
    func normalization() {
        let partial = WorkflowModelSetting.perType([.feature: .opus])
        #expect(
            partial.normalized
                == .perType([
                    .feature: .opus, .chore: .default, .spike: .default, .refactor: .default,
                ]))
        let allSame = WorkflowModelSetting.perType(
            Dictionary(uniqueKeysWithValues: IssueType.allCases.map { ($0, ModelChoice.opus) }))
        #expect(allSame.normalized == .uniform(.opus))
        #expect(WorkflowModelSetting.perType([:]).normalized == .uniform(.default))
    }
}
