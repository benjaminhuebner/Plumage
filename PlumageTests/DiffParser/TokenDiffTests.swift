import Testing

@testable import Plumage

@Suite("TokenDiff")
struct TokenDiffTests {
    private static func texts(_ ranges: [Range<String.Index>], in content: String) -> [String] {
        ranges.map { String(content[$0]) }
    }

    static let changeCases: [(old: String, new: String, removed: [String], inserted: [String])] = [
        ("let count = 1", "let count = 2", ["1"], ["2"]),
        ("foo(bar)", "foo(baz)", ["bar"], ["baz"]),
        ("foo bar", "foo  bar", [" "], ["  "]),
        ("foo", "foo ", [], [" "]),
        ("foo", "bar", ["foo"], ["bar"]),
        ("foo()", "bar[]", ["foo()"], ["bar[]"]),
        ("", "foo bar", [], ["foo bar"]),
        ("foo bar", "", ["foo bar"], []),
        ("", "", [], []),
        ("same line", "same line", [], []),
        ("a b", "a x b", [], ["x "]),
    ]

    @Test("classifies changed tokens via LCS and merges adjacent ranges", arguments: changeCases)
    func classification(
        testCase: (old: String, new: String, removed: [String], inserted: [String])
    )
        throws
    {
        let changes = try #require(TokenDiff.changes(old: testCase.old, new: testCase.new))
        #expect(Self.texts(changes.removed, in: testCase.old) == testCase.removed)
        #expect(Self.texts(changes.inserted, in: testCase.new) == testCase.inserted)
    }

    @Test("kept tokens around a change keep their soft tint")
    func keptTokensNotReported() throws {
        let old = "func makeThing(from value: Int) -> Thing"
        let new = "func makeThing(from value: Double) -> Thing"
        let changes = try #require(TokenDiff.changes(old: old, new: new))
        #expect(Self.texts(changes.removed, in: old) == ["Int"])
        #expect(Self.texts(changes.inserted, in: new) == ["Double"])
    }

    @Test("line beyond the length cap falls back to nil")
    func lengthCapFallback() {
        let long = String(repeating: "a", count: 100_000)
        #expect(TokenDiff.changes(old: long, new: "short") == nil)
        #expect(TokenDiff.changes(old: "short", new: long) == nil)
    }

    @Test("line beyond the token cap falls back to nil")
    func tokenCapFallback() {
        let manyTokens = String(repeating: "();", count: 100)
        #expect(TokenDiff.changes(old: manyTokens, new: "x") == nil)
    }

    @Test("caps are parameterizable")
    func customCaps() {
        #expect(TokenDiff.changes(old: "abcdef", new: "x", lengthCap: 5) == nil)
        #expect(TokenDiff.changes(old: "a b c", new: "x", tokenCap: 4) == nil)
        #expect(TokenDiff.changes(old: "abcdef", new: "x", lengthCap: 6) != nil)
    }

    @Test("whitespace-only change is reported, not treated as equal")
    func whitespaceOnlyChange() throws {
        let old = "\tvalue = 1"
        let new = "    value = 1"
        let changes = try #require(TokenDiff.changes(old: old, new: new))
        #expect(Self.texts(changes.removed, in: old) == ["\t"])
        #expect(Self.texts(changes.inserted, in: new) == ["    "])
    }

    @Test("emoji and multi-scalar content produces valid ranges")
    func emojiContent() throws {
        let old = "let flag = \"🇩🇪\""
        let new = "let flag = \"🇫🇷\""
        let changes = try #require(TokenDiff.changes(old: old, new: new))
        #expect(Self.texts(changes.removed, in: old) == ["🇩🇪"])
        #expect(Self.texts(changes.inserted, in: new) == ["🇫🇷"])
    }
}
