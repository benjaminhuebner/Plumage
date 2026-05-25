import Foundation
import Testing

@testable import Plumage

@Suite("DiffParser")
struct DiffParserTests {
    @Test("empty input returns empty array")
    func emptyInputReturnsEmptyArray() {
        let result = DiffParser.parse(unifiedDiff: "")
        #expect(result.isEmpty)
    }

    @Test("simple swift edit: one file, one hunk, context + add + remove")
    func simpleSwiftEdit() throws {
        let diff = try loadFixture("simple-swift-edit.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)

        let file = files[0]
        #expect(file.path == "Sources/Greeter.swift")
        #expect(file.status == .modified)
        #expect(file.modeChange == nil)
        try #require(file.hunks.count == 1)

        let hunk = file.hunks[0]
        #expect(hunk.oldStart == 1)
        #expect(hunk.oldCount == 5)
        #expect(hunk.newStart == 1)
        #expect(hunk.newCount == 6)

        let kinds: [LineKind] = hunk.lines.map { $0.kind }
        let expected: [LineKind] = [
            .context, .removed, .added, .added,
            .context, .removed, .added, .context, .context,
        ]
        #expect(kinds == expected)

        // First and last context lines preserve content (sans leading marker).
        #expect(hunk.lines.first?.content == "struct Greeter {")
        #expect(hunk.lines.last?.content == "}")
        // Tokens still empty until Task 3 wires LanguageDetector.
        let allTokensEmpty = hunk.lines.allSatisfy { $0.tokens.isEmpty }
        #expect(allTokensEmpty)
    }
}
