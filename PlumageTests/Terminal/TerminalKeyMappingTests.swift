import AppKit
import Testing

@testable import Plumage

struct TerminalKeyMappingTests {
    private func map(
        _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, characters: String? = nil
    ) -> String? {
        TerminalKeyMapping.sequence(
            keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    @Test func shiftEnterInsertsSoftNewline() {
        #expect(map(TerminalKeyMapping.returnKey, .shift) == "\n")
        #expect(map(TerminalKeyMapping.numpadEnterKey, .shift) == "\n")
    }

    @Test func plainEnterFallsThroughToSwiftTerm() {
        #expect(map(TerminalKeyMapping.returnKey, []) == nil)
        #expect(map(TerminalKeyMapping.numpadEnterKey, []) == nil)
    }

    @Test func commandBackspaceClearsWholeLine() {
        #expect(map(TerminalKeyMapping.deleteKey, .command) == "\u{05}\u{15}")
    }

    @Test func optionBackspaceDeletesWordBackward() {
        #expect(map(TerminalKeyMapping.deleteKey, .option) == "\u{17}")
    }

    @Test func forwardDeleteChords() {
        #expect(map(TerminalKeyMapping.forwardDeleteKey, .command) == "\u{0B}")
        #expect(map(TerminalKeyMapping.forwardDeleteKey, .option) == "\u{1B}d")
        #expect(map(TerminalKeyMapping.forwardDeleteKey, []) == nil)
    }

    @Test func commandArrowsJumpToLineEnds() {
        #expect(map(TerminalKeyMapping.leftArrowKey, .command) == "\u{01}")
        #expect(map(TerminalKeyMapping.rightArrowKey, .command) == "\u{05}")
    }

    @Test func optionArrowsMoveByWord() {
        #expect(map(TerminalKeyMapping.leftArrowKey, .option) == "\u{1B}b")
        #expect(map(TerminalKeyMapping.rightArrowKey, .option) == "\u{1B}f")
    }

    @Test func commandKClearsScreen() {
        #expect(map(6, .command, characters: "k") == "\u{0C}")
        #expect(map(6, .command, characters: "K") == "\u{0C}")
    }

    @Test func plainAndShiftedArrowsFallThrough() {
        #expect(map(TerminalKeyMapping.leftArrowKey, []) == nil)
        #expect(map(TerminalKeyMapping.rightArrowKey, .shift) == nil)
    }

    @Test func extraModifiersDisarmTheChord() {
        #expect(map(TerminalKeyMapping.deleteKey, [.command, .shift]) == nil)
        #expect(map(TerminalKeyMapping.leftArrowKey, [.option, .control]) == nil)
        #expect(map(TerminalKeyMapping.returnKey, [.shift, .command]) == nil)
    }

    @Test func hardwareOnlyFlagsAreIgnored() {
        // Arrow keys always carry .function/.numericPad; caps lock may be latched.
        #expect(map(TerminalKeyMapping.leftArrowKey, [.command, .function, .numericPad]) == "\u{01}")
        #expect(map(TerminalKeyMapping.deleteKey, [.option, .capsLock]) == "\u{17}")
    }

    @Test func unmappedKeysReturnNil() {
        #expect(map(0, .command, characters: "a") == nil)
        #expect(map(TerminalKeyMapping.deleteKey, []) == nil)
    }
}
