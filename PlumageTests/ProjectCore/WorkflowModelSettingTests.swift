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

    @Test("JSON object decodes to .perType with the given keys verbatim")
    func objectDecodesPerType() throws {
        let setting = try decode(#"{"feature": "opus", "chore": "haiku"}"#)
        #expect(setting == .perType([.feature: .opus, .chore: .haiku]))
    }

    @Test("custom-type keys load as their own types — the catalog is user-defined")
    func customKeysLoad() throws {
        let setting = try decode(#"{"feature": "opus", "epic": "haiku"}"#)
        #expect(setting.choice(for: .feature) == .opus)
        #expect(setting.choice(for: IssueType(rawValue: "epic")) == .haiku)
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
        let value = try encodeToJSONObject(.uniform(.haiku))
        #expect(value as? String == "haiku")
    }

    @Test(".perType encodes its entries verbatim")
    func perTypeEncodesObject() throws {
        let value = try encodeToJSONObject(.perType([.feature: .opus, .chore: .haiku]))
        let dict = try #require(value as? [String: String])
        #expect(dict == ["feature": "opus", "chore": "haiku"])
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

    @Test("normalized(for:) completes missing types, drops stale ones, collapses identical maps")
    func normalization() {
        let types = IssueTypeCatalog.builtIn.types
        let partial = WorkflowModelSetting.perType([.feature: .opus])
        #expect(
            partial.normalized(for: types)
                == .perType([
                    .feature: .opus, .chore: .default, .spike: .default, .refactor: .default,
                ]))
        let allSame = WorkflowModelSetting.perType(
            Dictionary(uniqueKeysWithValues: types.map { ($0, ModelChoice.opus) }))
        #expect(allSame.normalized(for: types) == .uniform(.opus))
        #expect(WorkflowModelSetting.perType([:]).normalized(for: types) == .uniform(.default))
        let stale = WorkflowModelSetting.perType([IssueType(rawValue: "ghost"): .opus])
        #expect(stale.normalized(for: types) == .uniform(.default))
    }
}
