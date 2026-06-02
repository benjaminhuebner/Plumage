import Foundation
import Testing

@testable import Plumage

@Suite("PRMarkdownParser")
struct PRMarkdownParserTests {
    private func headingText(_ block: PRMarkdownParser.Block) -> (Int, String)? {
        guard case .heading(let level, let text) = block else { return nil }
        return (level, String(text.characters))
    }

    @Test("parses headings with levels 1...6")
    func headings() {
        let blocks = PRMarkdownParser.parse("# One\n## Two\n###### Six")
        let headings = blocks.compactMap(headingText)
        #expect(headings.count == 3)
        #expect(headings[0].0 == 1 && headings[0].1 == "One")
        #expect(headings[1].0 == 2 && headings[1].1 == "Two")
        #expect(headings[2].0 == 6 && headings[2].1 == "Six")
    }

    @Test("a 7-hash line is a paragraph, not a heading")
    func headingLevelCap() {
        let blocks = PRMarkdownParser.parse("####### TooDeep")
        #expect(headingText(blocks[0]) == nil)
        if case .paragraph = blocks[0] {} else { Issue.record("expected paragraph") }
    }

    @Test("a hash with no following space is a paragraph")
    func headingNeedsSpace() {
        let blocks = PRMarkdownParser.parse("#NoSpace")
        if case .paragraph = blocks[0] {} else { Issue.record("expected paragraph") }
    }

    @Test("bullets accept - and * markers")
    func bullets() {
        let blocks = PRMarkdownParser.parse("- first\n* second")
        let bulletCount = blocks.filter {
            if case .bullet = $0 { return true }
            return false
        }.count
        #expect(bulletCount == 2)
    }

    @Test("code fence captures inner lines verbatim and isn't parsed as markdown")
    func codeFence() {
        let blocks = PRMarkdownParser.parse("```\n# not a heading\n- not a bullet\n```")
        #expect(blocks.count == 1)
        guard case .codeBlock(let text) = blocks[0] else {
            Issue.record("expected code block")
            return
        }
        #expect(text == "# not a heading\n- not a bullet")
    }

    @Test("an unterminated code fence consumes the rest of the input")
    func unterminatedFence() {
        let blocks = PRMarkdownParser.parse("```\nline one\nline two")
        #expect(blocks.count == 1)
        guard case .codeBlock(let text) = blocks[0] else {
            Issue.record("expected code block")
            return
        }
        #expect(text == "line one\nline two")
    }

    @Test("blank lines become blank blocks")
    func blanks() {
        let blocks = PRMarkdownParser.parse("a\n\nb")
        #expect(blocks.count == 3)
        if case .blank = blocks[1] {} else { Issue.record("expected blank in the middle") }
    }

    @Test("empty input yields no blocks")
    func empty() {
        #expect(
            PRMarkdownParser.parse("").allSatisfy {
                if case .blank = $0 { return true }
                return false
            })
    }
}
