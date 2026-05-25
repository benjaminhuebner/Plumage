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

    @Test("binary file: status .binary, no hunks")
    func binaryFile() throws {
        let diff = try loadFixture("binary-file.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Assets/logo.png")
        #expect(file.status == .binary)
        #expect(file.hunks.isEmpty)
    }

    @Test("submodule bump: status .submodule(from:, to:) from index SHAs")
    func submoduleBump() throws {
        let diff = try loadFixture("submodule-bump.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Vendor/lib")
        #expect(file.status == .submodule(from: "abc1234", to: "def5678"))
    }

    @Test("submodule initial add: from = 0000000, to = SHA")
    func submoduleInitialAdd() throws {
        let diff = try loadFixture("submodule-initial-add.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Vendor/newlib")
        #expect(file.status == .submodule(from: "0000000", to: "7777777"))
    }

    @Test("symlink change: status stays .modified, body has target paths")
    func symlinkChange() throws {
        let diff = try loadFixture("symlink-change.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "link")
        #expect(file.status == .modified)
        let hunk = try #require(file.hunks.first)
        let removed = try #require(hunk.lines.first { $0.kind == .removed })
        let added = try #require(hunk.lines.first { $0.kind == .added })
        #expect(removed.content == "old/target/path")
        #expect(added.content == "new/target/path")
    }

    @Test("no trailing newline marker tags the preceding +/- line")
    func noTrailingNewline() throws {
        let diff = try loadFixture("no-trailing-newline.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let hunk = try #require(files[0].hunks.first)
        let removed = try #require(hunk.lines.first { $0.kind == .removed })
        let added = try #require(hunk.lines.first { $0.kind == .added })
        #expect(removed.hasNoTrailingNewline)
        #expect(added.hasNoTrailingNewline)
        // The leading context line is unaffected.
        #expect(hunk.lines.first?.hasNoTrailingNewline == false)
    }

    @Test("empty fixture parses to empty array")
    func emptyFixture() throws {
        let diff = try loadFixture("empty.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        #expect(files.isEmpty)
    }

    @Test("multi-file diff: parses ≥ 3 files of different statuses")
    func multiFile() throws {
        let diff = try loadFixture("multi-file.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 4)

        #expect(files[0].path == "Sources/Existing.swift")
        #expect(files[0].status == .modified)
        #expect(files[0].hunks.count == 1)

        #expect(files[1].path == "Sources/Old.swift")
        #expect(files[1].status == .deleted)

        #expect(files[2].path == "Sources/Brand.swift")
        #expect(files[2].status == .added)

        #expect(files[3].path == "Vendor/lib")
        #expect(files[3].status == .submodule(from: "abc1234", to: "def5678"))
    }

    @Test("malformed hunk header drops only its file, others survive")
    func malformedHunkRecovery() throws {
        let diff = try loadFixture("malformed-hunk.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        let paths = files.map(\.path)
        #expect(paths == ["Sources/Good.swift", "Sources/AlsoGood.swift"])
    }

    @Test("determinism: parse twice → equatable identical output")
    func deterministicOutput() throws {
        let diff = try loadFixture("multi-file.diff")
        let first = DiffParser.parse(unifiedDiff: diff)
        let second = DiffParser.parse(unifiedDiff: diff)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("forgiveness: BOM + CRLF input normalises")
    func bomAndCRLF() throws {
        let body = try loadFixture("simple-swift-edit.diff")
        let bomCRLF = "\u{FEFF}" + body.replacingOccurrences(of: "\n", with: "\r\n")
        let normal = DiffParser.parse(unifiedDiff: body)
        let weird = DiffParser.parse(unifiedDiff: bomCRLF)
        #expect(normal == weird)
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

    // MARK: - Regression: multi-hunk file with a malformed second @@

    @Test("malformed second hunk preserves prior good hunks of same file")
    func multiHunkSecondMalformed() throws {
        let diff = try loadFixture("multi-hunk-second-malformed.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/Partial.swift")
        // The first hunk is well-formed and must survive the malformed second.
        try #require(file.hunks.count == 1)
        let kinds = file.hunks[0].lines.map { $0.kind }
        #expect(kinds == [.removed, .added])
    }

    // MARK: - Path handling

    @Test("path with spaces survives extractPath")
    func pathWithSpaces() throws {
        let diff = try loadFixture("path-with-spaces.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        #expect(files[0].path == "Sources/has space.txt")
    }

    @Test("C-quoted path in diff --git header is recovered without surrounding quotes")
    func pathQuoted() throws {
        let diff = try loadFixture("path-quoted.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        #expect(files[0].path == "Sources/qu oted.txt")
    }

    @Test("+++ b/<path> updates the file path when diff --git disagrees")
    func adoptDestinationPathFromTripletPlus() {
        let diff = """
            diff --git a/old/name b/old/name
            index 1111111..2222222 100644
            --- a/old/name
            +++ b/new/name
            @@ -1,1 +1,1 @@
            -old
            +new
            """
        let files = DiffParser.parse(unifiedDiff: diff)
        #expect(files.first?.path == "new/name")
    }

    @Test("diff --git with no path emits no FileDiff")
    func emptyPathSkipped() {
        // `diff --git ` with no a/ b/ paths is malformed; should be skipped.
        let diff = "diff --git \n@@ -1,1 +1,1 @@\n-a\n+b\n"
        let files = DiffParser.parse(unifiedDiff: diff)
        #expect(files.isEmpty)
    }

    // MARK: - Status guards

    @Test("--- /dev/null does NOT flip an explicit .added to .deleted via stray +++ /dev/null")
    func addedDoesNotFlipToDeleted() throws {
        let diff = try loadFixture("added-no-flip.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        // The fixture has a malformed `+++ /dev/null` after `new file mode`;
        // status must remain .added (override guard refuses to flip).
        #expect(files[0].status == .added)
    }

    @Test(".modified with pending modeChange is not stomped by /dev/null")
    func modeChangeSurvivesDevNullOverride() {
        let diff = """
            diff --git a/run.sh b/run.sh
            old mode 100644
            new mode 100755
            index 1111111..2222222
            +++ /dev/null
            """
        let files = DiffParser.parse(unifiedDiff: diff)
        try? #require(files.count == 1)
        #expect(files.first?.status == .modified)
        #expect(files.first?.modeChange == ModeChange(old: "100644", new: "100755"))
    }

    // MARK: - Mode change pair

    @Test("half-formed mode change (only old mode) emits modeChange == nil")
    func halfFormedModeChange() throws {
        let diff = try loadFixture("half-mode-change.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        #expect(files[0].modeChange == nil)
    }

    // MARK: - Contradictory status + body

    @Test("binary status drops any stray text hunks")
    func binaryDropsHunks() {
        let diff = """
            diff --git a/asset.bin b/asset.bin
            index 1111111..2222222 100644
            --- a/asset.bin
            +++ b/asset.bin
            Binary files a/asset.bin and b/asset.bin differ
            @@ -1,1 +1,1 @@
            -stray
            +stray
            """
        let files = DiffParser.parse(unifiedDiff: diff)
        try? #require(files.count == 1)
        #expect(files.first?.status == .binary)
        #expect(files.first?.hunks.isEmpty == true)
    }

    // MARK: - Body line edge cases

    @Test("empty body line inside a hunk parses as a blank context line")
    func emptyContextLine() throws {
        let diff = try loadFixture("empty-context-line.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let hunk = try #require(files[0].hunks.first)
        let kinds = hunk.lines.map { $0.kind }
        #expect(kinds == [.context, .context, .removed, .added])
        // The middle context line is blank.
        #expect(hunk.lines[1].content.isEmpty)
    }

    // MARK: - Tokenisation

    @Test("JSON string with escaped backslash before closing quote tokenises")
    func jsonEscapedBackslash() throws {
        let diff = try loadFixture("json-escaped-backslash.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let hunk = try #require(files[0].hunks.first)
        let added = try #require(hunk.lines.first { $0.kind == .added })
        // The added line contains "C:\\new\\". Without the escape-aware regex
        // the closing quote would be consumed as part of \", failing to match.
        #expect(added.tokens.contains { $0.kind == .string })
    }

    @Test("emoji content: token ranges round-trip via Range<String.Index>")
    func emojiTokenRanges() throws {
        let diff = try loadFixture("emoji-content.diff")
        let files = DiffParser.parse(unifiedDiff: diff)
        try #require(files.count == 1)
        let hunk = try #require(files[0].hunks.first)
        let added = try #require(hunk.lines.first { $0.kind == .added })
        // Each token range must produce a valid Substring without trapping.
        for token in added.tokens {
            _ = added.content[token.range]
        }
    }
}
