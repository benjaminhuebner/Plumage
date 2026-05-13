import Foundation
import Testing

@testable import Plumage

@Suite("TextOffset")
struct TextOffsetTests {
    @Test("offset of line 1 column 1 in non-empty text is 0")
    func line1Column1() {
        let text = "abc\ndef\n"
        #expect(TextOffset.offset(ofLine: 1, column: 1, in: text) == 0)
    }

    @Test("offset of line 1 column 3 returns column-1")
    func line1Column3() {
        let text = "abc\ndef\n"
        #expect(TextOffset.offset(ofLine: 1, column: 3, in: text) == 2)
    }

    @Test("offset of line 2 column 1 is past first newline")
    func line2Column1() {
        let text = "abc\ndef\n"
        #expect(TextOffset.offset(ofLine: 2, column: 1, in: text) == 4)
    }

    @Test("offset of line 2 column 2 lands on second char of second line")
    func line2Column2() {
        let text = "abc\ndef\n"
        #expect(TextOffset.offset(ofLine: 2, column: 2, in: text) == 5)
    }

    @Test("offset past EOF is clamped to end of text")
    func pastEOF() {
        let text = "abc"
        let result = TextOffset.offset(ofLine: 10, column: 10, in: text)
        #expect(result == text.utf16.count)
    }

    @Test("zero or negative line/column treated as 1")
    func clampedToOne() {
        let text = "abc\ndef"
        #expect(TextOffset.offset(ofLine: 0, column: 0, in: text) == 0)
        #expect(TextOffset.offset(ofLine: -5, column: -5, in: text) == 0)
    }

    @Test("offset uses UTF-16 units, stable across surrogate pairs")
    func utf16Stability() {
        // "😀" (U+1F600) is one Character but two UTF-16 code units.
        let text = "😀x\nnext"
        // line 1 column 3 → past both surrogate units → offset 2.
        #expect(TextOffset.offset(ofLine: 1, column: 3, in: text) == 2)
        // line 2 column 1 → past "😀x\n" = 4 UTF-16 units.
        #expect(TextOffset.offset(ofLine: 2, column: 1, in: text) == 4)
    }
}
