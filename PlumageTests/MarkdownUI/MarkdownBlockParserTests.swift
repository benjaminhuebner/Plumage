import Foundation
import Testing

@testable import Plumage

@Suite("MarkdownBlockParser")
struct MarkdownBlockParserTests {
    private func headingText(_ block: MarkdownBlockParser.Block) -> (Int, String)? {
        guard case .heading(let level, let text) = block else { return nil }
        return (level, String(text.characters))
    }

    @Test("parses headings with levels 1...6")
    func headings() {
        let blocks = MarkdownBlockParser.parse("# One\n## Two\n###### Six")
        let headings = blocks.compactMap(headingText)
        #expect(headings.count == 3)
        #expect(headings[0].0 == 1 && headings[0].1 == "One")
        #expect(headings[1].0 == 2 && headings[1].1 == "Two")
        #expect(headings[2].0 == 6 && headings[2].1 == "Six")
    }

    @Test("a 7-hash line is a paragraph, not a heading")
    func headingLevelCap() {
        let blocks = MarkdownBlockParser.parse("####### TooDeep")
        #expect(headingText(blocks[0]) == nil)
        if case .paragraph = blocks[0] {} else { Issue.record("expected paragraph") }
    }

    @Test("a hash with no following space is a paragraph")
    func headingNeedsSpace() {
        let blocks = MarkdownBlockParser.parse("#NoSpace")
        if case .paragraph = blocks[0] {} else { Issue.record("expected paragraph") }
    }

    @Test("bullets accept - and * markers")
    func bullets() {
        let blocks = MarkdownBlockParser.parse("- first\n* second")
        let bulletCount = blocks.filter {
            if case .bullet = $0 { return true }
            return false
        }.count
        #expect(bulletCount == 2)
    }

    @Test("code fence captures inner lines verbatim and isn't parsed as markdown")
    func codeFence() {
        let blocks = MarkdownBlockParser.parse("```\n# not a heading\n- not a bullet\n```")
        #expect(blocks.count == 1)
        guard case .codeBlock(let text) = blocks[0] else {
            Issue.record("expected code block")
            return
        }
        #expect(text == "# not a heading\n- not a bullet")
    }

    @Test("an unterminated code fence consumes the rest of the input")
    func unterminatedFence() {
        let blocks = MarkdownBlockParser.parse("```\nline one\nline two")
        #expect(blocks.count == 1)
        guard case .codeBlock(let text) = blocks[0] else {
            Issue.record("expected code block")
            return
        }
        #expect(text == "line one\nline two")
    }

    @Test("blank lines become blank blocks")
    func blanks() {
        let blocks = MarkdownBlockParser.parse("a\n\nb")
        #expect(blocks.count == 3)
        if case .blank = blocks[1] {} else { Issue.record("expected blank in the middle") }
    }

    @Test("empty input yields no blocks")
    func empty() {
        #expect(
            MarkdownBlockParser.parse("").allSatisfy {
                if case .blank = $0 { return true }
                return false
            })
    }

    @Test("ordered items accept . and ) markers and keep their numbers")
    func orderedItems() throws {
        let blocks = MarkdownBlockParser.parse("1. first\n2) second")
        try #require(blocks.count == 2)
        guard case .orderedItem(let indent, let number, let text) = blocks[0] else {
            Issue.record("expected ordered item")
            return
        }
        #expect(indent == 0 && number == 1 && String(text.characters) == "first")
        guard case .orderedItem(_, let second, _) = blocks[1] else {
            Issue.record("expected ordered item")
            return
        }
        #expect(second == 2)
    }

    @Test("a number without list marker stays a paragraph")
    func numberWithoutMarker() {
        for input in ["1.no space", "12345678901. overflow", "1x. nope"] {
            let blocks = MarkdownBlockParser.parse(input)
            guard case .paragraph = blocks[0] else {
                Issue.record("expected paragraph for \(input)")
                return
            }
        }
    }

    @Test("nested list items carry their indent level")
    func nestedLists() throws {
        let blocks = MarkdownBlockParser.parse("- top\n  - nested\n    1. deep")
        try #require(blocks.count == 3)
        guard case .bullet(let topIndent, _) = blocks[0],
            case .bullet(let nestedIndent, _) = blocks[1],
            case .orderedItem(let deepIndent, _, _) = blocks[2]
        else {
            Issue.record("expected bullet, bullet, ordered")
            return
        }
        #expect(topIndent == 0)
        #expect(nestedIndent == 1)
        #expect(deepIndent == 2)
    }

    @Test("task-list items parse done state, including uppercase X")
    func taskItems() throws {
        let blocks = MarkdownBlockParser.parse("- [ ] open\n- [x] done\n- [X] also done")
        try #require(blocks.count == 3)
        guard case .taskItem(_, let open, let openText) = blocks[0],
            case .taskItem(_, let done, _) = blocks[1],
            case .taskItem(_, let upper, _) = blocks[2]
        else {
            Issue.record("expected three task items")
            return
        }
        #expect(!open && String(openText.characters) == "open")
        #expect(done)
        #expect(upper)
    }

    @Test("a bracket without task marker shape stays a bullet")
    func nonTaskBracket() {
        let blocks = MarkdownBlockParser.parse("- [link](https://example.com) text")
        guard case .bullet = blocks[0] else {
            Issue.record("expected plain bullet")
            return
        }
    }

    @Test("pipe tables parse headers and rows")
    func table() throws {
        let blocks = MarkdownBlockParser.parse(
            "| Col A | Col B |\n|---|:--:|\n| a1 | b1 |\n| a2 | b2 |")
        try #require(blocks.count == 1)
        guard case .table(let headers, let rows) = blocks[0] else {
            Issue.record("expected table")
            return
        }
        #expect(headers.map { String($0.characters) } == ["Col A", "Col B"])
        #expect(rows.count == 2)
        #expect(rows[0].map { String($0.characters) } == ["a1", "b1"])
        #expect(rows[1].map { String($0.characters) } == ["a2", "b2"])
    }

    @Test("a pipe line without delimiter row degrades to a paragraph")
    func tableWithoutDelimiter() {
        let blocks = MarkdownBlockParser.parse("| a | b |\n| 1 | 2 |")
        #expect(
            blocks.allSatisfy {
                if case .paragraph = $0 { return true }
                return false
            })
    }

    @Test("ragged table rows keep every cell without crashing")
    func raggedTableRows() throws {
        let blocks = MarkdownBlockParser.parse("| a | b |\n|---|---|\n| only |\n| 1 | 2 | 3 |")
        try #require(blocks.count == 1)
        guard case .table(_, let rows) = blocks[0] else {
            Issue.record("expected table")
            return
        }
        #expect(rows[0].map { String($0.characters) } == ["only"])
        #expect(rows[1].map { String($0.characters) } == ["1", "2", "3"])
    }

    @Test("the table ends at the first non-pipe line")
    func tableTermination() throws {
        let blocks = MarkdownBlockParser.parse("| a |\n|---|\n| 1 |\n\nafter")
        try #require(blocks.count == 3)
        guard case .table = blocks[0], case .blank = blocks[1], case .paragraph = blocks[2]
        else {
            Issue.record("expected table, blank, paragraph")
            return
        }
    }

    @Test("a lone delimiter row is not a table")
    func loneDelimiter() {
        let blocks = MarkdownBlockParser.parse("|---|---|")
        guard case .paragraph = blocks[0] else {
            Issue.record("expected paragraph")
            return
        }
    }

    private func paragraphText(_ block: MarkdownBlockParser.Block) -> AttributedString? {
        guard case .paragraph(let text) = block else { return nil }
        return text
    }

    private func hasIntent(_ text: AttributedString, _ intent: InlinePresentationIntent) -> Bool {
        text.runs.contains { $0.inlinePresentationIntent?.contains(intent) == true }
    }

    private func links(in text: AttributedString) -> [URL] {
        text.runs.compactMap(\.link)
    }

    @Test("emphasis, strong, and inline code become styled runs")
    func inlineStyles() throws {
        let blocks = MarkdownBlockParser.parse("*em* and **strong** and `code`")
        let text = try #require(paragraphText(blocks[0]))
        #expect(hasIntent(text, .emphasized))
        #expect(hasIntent(text, .stronglyEmphasized))
        #expect(hasIntent(text, .code))
        #expect(String(text.characters) == "em and strong and code")
    }

    @Test("http and https links stay clickable")
    func webLinksPreserved() throws {
        let blocks = MarkdownBlockParser.parse("[a](https://example.com) [b](http://example.org)")
        let text = try #require(paragraphText(blocks[0]))
        let urls = links(in: text)
        #expect(urls.count == 2)
        #expect(urls.map(\.scheme?.localizedLowercase) == ["https", "http"])
    }

    @Test(
        "dangerous and relative link schemes render as inert text",
        arguments: [
            "[open](javascript:alert(1))",
            "[open](file:///etc/passwd)",
            "[open](ftp://example.com)",
            "[open](relative/path.md)",
        ])
    func dangerousLinksInert(input: String) throws {
        let blocks = MarkdownBlockParser.parse(input)
        let text = try #require(paragraphText(blocks[0]))
        #expect(links(in: text).isEmpty)
        #expect(String(text.characters) == "open")
    }

    @Test("unclosed emphasis degrades to literal text without loss")
    func unclosedEmphasis() throws {
        let blocks = MarkdownBlockParser.parse("*unclosed emphasis")
        let text = try #require(paragraphText(blocks[0]))
        #expect(String(text.characters).contains("unclosed emphasis"))
    }

    @Test("inline styles apply inside list items and table cells")
    func inlineInsideBlocks() throws {
        let blocks = MarkdownBlockParser.parse("- **bold** item\n\n| [x](javascript:x) |\n|---|")
        guard case .bullet(_, let bulletText) = blocks[0] else {
            Issue.record("expected bullet")
            return
        }
        #expect(hasIntent(bulletText, .stronglyEmphasized))
        guard case .table(let headers, _) = blocks[2] else {
            Issue.record("expected table")
            return
        }
        let header = try #require(headers.first)
        #expect(links(in: header).isEmpty)
        #expect(String(header.characters) == "x")
    }
}
