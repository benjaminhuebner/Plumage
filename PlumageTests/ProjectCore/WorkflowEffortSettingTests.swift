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

    @Test("JSON object decodes to .perType with the given keys verbatim")
    func objectDecodesPerType() throws {
        let setting = try decode(#"{"feature": "max", "chore": "low"}"#)
        #expect(setting == .perType([.feature: .max, .chore: .low]))
    }

    @Test("custom-type keys load as their own types — the catalog is user-defined")
    func customKeysLoad() throws {
        let setting = try decode(#"{"feature": "max", "epic": "low"}"#)
        #expect(setting.choice(for: .feature) == .max)
        #expect(setting.choice(for: IssueType(rawValue: "epic")) == .low)
        #expect(setting.choice(for: .chore) == nil)
    }

    @Test("empty object decodes as an empty per-type map (every lookup nil)")
    func emptyObjectIsEmptyMap() throws {
        let setting = try decode("{}")
        #expect(setting == .perType([:]))
        #expect(setting.choice(for: .feature) == nil)
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

    @Test(".perType encodes its entries verbatim")
    func perTypeEncodesObject() throws {
        let value = try encodeToJSONObject(.perType([.feature: .max, .chore: .low]))
        let dict = try #require(value as? [String: String])
        #expect(dict == ["feature": "max", "chore": "low"])
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

    @Test("normalized(for:) completes missing types, drops stale ones, collapses identical maps")
    func normalization() {
        let types = IssueTypeCatalog.builtIn.types
        let partial = WorkflowEffortSetting.perType([.feature: .max])
        #expect(
            partial.normalized(for: types)
                == .perType([
                    .feature: .max, .chore: .default, .spike: .default, .refactor: .default,
                ]))
        let allSame = WorkflowEffortSetting.perType(
            Dictionary(uniqueKeysWithValues: types.map { ($0, EffortLevel.max) }))
        #expect(allSame.normalized(for: types) == .uniform(.max))
        #expect(WorkflowEffortSetting.perType([:]).normalized(for: types) == .uniform(.default))
        let stale = WorkflowEffortSetting.perType([IssueType(rawValue: "ghost"): .max])
        #expect(stale.normalized(for: types) == .uniform(.default))
    }
}
