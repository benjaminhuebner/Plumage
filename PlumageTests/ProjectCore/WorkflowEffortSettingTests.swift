import Foundation
import Testing

@testable import Plumage

@Suite("WorkflowEffortSetting string-or-object Codable")
struct WorkflowEffortSettingTests {
    private func decode(_ json: String) throws -> WorkflowEffortSetting {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(WorkflowEffortSetting.self, from: data)
    }

    private func encodeToJSONObject(_ setting: WorkflowEffortSetting) throws -> Any {
        let data = try JSONEncoder().encode(setting)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @Test("JSON string decodes to .uniform")
    func stringDecodesUniform() throws {
        #expect(try decode("\"max\"") == .uniform(.max))
        #expect(try decode("\"default\"") == .uniform(.default))
    }

    @Test("an unknown level inside a uniform string decodes to default")
    func unknownStringDecodesDefault() throws {
        #expect(try decode("\"ultra\"") == .uniform(.default))
    }

    @Test("JSON object decodes to .perType with all four types completed")
    func objectDecodesPerType() throws {
        let setting = try decode(#"{"feature": "max", "chore": "low"}"#)
        #expect(
            setting
                == .perType([
                    .feature: .max, .chore: .low, .spike: .default, .refactor: .default,
                ]))
    }

    @Test("object with identical values collapses to .uniform on decode")
    func identicalObjectCollapses() throws {
        let setting = try decode(
            #"{"feature": "high", "chore": "high", "spike": "high", "refactor": "high"}"#)
        #expect(setting == .uniform(.high))
    }

    @Test("unknown object keys are ignored on decode")
    func unknownKeysIgnored() throws {
        let setting = try decode(#"{"feature": "max", "epic": "low"}"#)
        #expect(setting.choice(for: .feature) == .max)
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
        let value = try encodeToJSONObject(.uniform(.high))
        #expect(value as? String == "high")
    }

    @Test(".perType with differing values encodes as full four-key object")
    func perTypeEncodesObject() throws {
        let value = try encodeToJSONObject(.perType([.feature: .max, .chore: .low]))
        let dict = try #require(value as? [String: String])
        #expect(
            dict == [
                "feature": "max", "chore": "low", "spike": "default", "refactor": "default",
            ])
    }

    @Test(".perType with identical values encodes as plain string")
    func perTypeCollapsesOnEncode() throws {
        let map = Dictionary(uniqueKeysWithValues: IssueType.allCases.map { ($0, EffortLevel.high) })
        let value = try encodeToJSONObject(.perType(map))
        #expect(value as? String == "high")
    }

    @Test("mixed setting round-trips")
    func mixedRoundTrip() throws {
        let original = WorkflowEffortSetting.perType([
            .feature: .max, .chore: .low, .spike: .high, .refactor: .default,
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkflowEffortSetting.self, from: data)
        #expect(decoded == original)
    }

    @Test("choice(for:) returns per-type hit, nil for missing, uniform for uniform")
    func choiceLookup() {
        let mixed = WorkflowEffortSetting.perType([.feature: .max])
        #expect(mixed.choice(for: .feature) == .max)
        #expect(mixed.choice(for: .spike) == nil)
        #expect(WorkflowEffortSetting.uniform(.high).choice(for: .refactor) == .high)
    }

    @Test("normalized completes missing types and collapses identical maps")
    func normalization() {
        let partial = WorkflowEffortSetting.perType([.feature: .max])
        #expect(
            partial.normalized
                == .perType([
                    .feature: .max, .chore: .default, .spike: .default, .refactor: .default,
                ]))
        let allSame = WorkflowEffortSetting.perType(
            Dictionary(uniqueKeysWithValues: IssueType.allCases.map { ($0, EffortLevel.max) }))
        #expect(allSame.normalized == .uniform(.max))
        #expect(WorkflowEffortSetting.perType([:]).normalized == .uniform(.default))
    }
}
