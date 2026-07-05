import Foundation
import Testing

@testable import Plumage

@Suite("JSONMerge")
struct JSONMergeTests {
    private func merge(_ variants: [String]) throws -> Any {
        let data = try JSONMerge.merge(variants: variants.map { Data($0.utf8) })
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @Test("Objects merge key-wise, later scalar values win")
    func objectDeepMerge() throws {
        let merged = try #require(
            try merge([
                #"{"a": 1, "nested": {"x": 1, "y": 2}}"#,
                #"{"b": 2, "nested": {"y": 3, "z": 4}}"#,
            ]) as? [String: Any])
        #expect(merged["a"] as? Int == 1)
        #expect(merged["b"] as? Int == 2)
        let nested = try #require(merged["nested"] as? [String: Any])
        #expect(nested["x"] as? Int == 1)
        #expect(nested["y"] as? Int == 3)
        #expect(nested["z"] as? Int == 4)
    }

    @Test("Arrays append new elements and skip ones the base already has")
    func arrayAppendDedup() throws {
        let merged = try #require(
            try merge([#"{"list": ["a", "b"]}"#, #"{"list": ["b", "c"]}"#]) as? [String: Any])
        #expect(merged["list"] as? [String] == ["a", "b", "c"])
    }

    @Test("A type conflict takes the later value wholesale")
    func typeConflictLaterWins() throws {
        let merged = try #require(
            try merge([#"{"k": {"a": 1}}"#, #"{"k": [1, 2]}"#]) as? [String: Any])
        #expect(merged["k"] as? [Int] == [1, 2])
    }

    @Test("Three variants merge in order")
    func threeVariants() throws {
        let merged = try #require(
            try merge([#"{"v": 1}"#, #"{"v": 2, "w": 1}"#, #"{"v": 3}"#]) as? [String: Any])
        #expect(merged["v"] as? Int == 3)
        #expect(merged["w"] as? Int == 1)
    }

    @Test("Boolean and numeric array elements stay distinct in dedup")
    func arrayBoolNumberDistinct() throws {
        let numbersFirst = try #require(
            try merge([#"{"list": [0, 1]}"#, #"{"list": [true]}"#]) as? [String: Any])
        #expect((numbersFirst["list"] as? [Any])?.count == 3)
        let booleanFirst = try #require(
            try merge([#"{"list": [true]}"#, #"{"list": [1]}"#]) as? [String: Any])
        #expect((booleanFirst["list"] as? [Any])?.count == 2)
    }

    @Test("Invalid JSON throws instead of guessing")
    func invalidJSONThrows() {
        #expect(throws: (any Error).self) {
            try JSONMerge.merge(variants: [Data("{not json".utf8), Data("{}".utf8)])
        }
    }
}
