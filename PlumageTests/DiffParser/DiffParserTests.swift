import Foundation
import LanguageSupport
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
        // Swift tokeniser hits at least the `struct` keyword and `String`
        // identifier spans.
        let firstLineTokens = hunk.lines[0].tokens
        let hasKeyword = firstLineTokens.contains { $0.kind == .keyword }
        #expect(hasKeyword)
    }

    @Test("markdown edit: inline-code spans tokenised as string")
    func markdownInlineCode() throws {
        let diff = try loadFixture("markdown-edit.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        #expect(files[0].path == "README.md")

        let hunk = try #require(files[0].hunks.first)
        // The removed and added lines both contain a `…` inline-code span.
        let removed = try #require(hunk.lines.first { $0.kind == .removed })
        let added = try #require(hunk.lines.first { $0.kind == .added })
        #expect(removed.tokens.contains { $0.kind == .string })
        #expect(added.tokens.contains { $0.kind == .string })
    }

    @Test("file added: status .added, all body lines are .added")
    func fileAdded() throws {
        let diff = try loadFixture("file-added.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/NewFile.swift")
        #expect(file.status == .added)
        let hunk = try #require(file.hunks.first)
        let kinds = Set(hunk.lines.map { $0.kind })
        #expect(kinds == [.added])
    }

    @Test("file deleted: status .deleted, all body lines are .removed")
    func fileDeleted() throws {
        let diff = try loadFixture("file-deleted.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/Legacy.swift")
        #expect(file.status == .deleted)
        let hunk = try #require(file.hunks.first)
        let kinds = Set(hunk.lines.map { $0.kind })
        #expect(kinds == [.removed])
    }

    @Test("rename: status .renamed(from:) keeps destination path")
    func fileRename() throws {
        let diff = try loadFixture("file-rename.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/Renamed.swift")
        #expect(file.status == .renamed(from: "Sources/Old.swift"))
    }

    @Test("copy: status .copied(from:) keeps destination path")
    func fileCopy() throws {
        let diff = try loadFixture("file-copy.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/Variant.swift")
        #expect(file.status == .copied(from: "Sources/Template.swift"))
    }

    @Test("mode change: modeChange captures old + new, no hunks")
    func modeChangeOnly() throws {
        let diff = try loadFixture("mode-change.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "scripts/run.sh")
        #expect(file.status == .modified)
        #expect(file.modeChange == ModeChange(old: "100644", new: "100755"))
        #expect(file.hunks.isEmpty)
    }

    @Test("json edit: string + number + reserved tokens recognised")
    func jsonTokens() throws {
        let diff = try loadFixture("json-config-change.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        #expect(files[0].path == "config.json")

        let hunk = try #require(files[0].hunks.first)
        let removed = try #require(hunk.lines.first { $0.kind == .removed })
        let added = try #require(hunk.lines.first { $0.kind == .added })
        let trueLine = try #require(hunk.lines.first { $0.content.contains("true") })

        #expect(removed.tokens.contains { $0.kind == .string })
        #expect(removed.tokens.contains { $0.kind == .number })
        #expect(added.tokens.contains { $0.kind == .number })
        #expect(trueLine.tokens.contains { $0.kind == .keyword })
    }
}
