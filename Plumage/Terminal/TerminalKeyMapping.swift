import AppKit

// Maps macOS-native editing chords to the readline-style sequences claude's
// REPL understands (iTerm2 "Natural Text Editing" semantics), so the input
// line edits like a native text field.
nonisolated enum TerminalKeyMapping {
    static let returnKey: UInt16 = 36
    static let numpadEnterKey: UInt16 = 76
    static let deleteKey: UInt16 = 51
    static let forwardDeleteKey: UInt16 = 117
    static let leftArrowKey: UInt16 = 123
    static let rightArrowKey: UInt16 = 124

    static func sequence(
        keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags
    ) -> String? {
        // Arrows/enter carry .function/.numericPad and caps lock is noise —
        // compare only the chord-defining modifiers.
        let chord = modifiers.intersection([.shift, .command, .option, .control])
        switch keyCode {
        case Self.returnKey, Self.numpadEnterKey:
            // claude's REPL submits on \r and treats \n as a soft newline.
            return chord == .shift ? "\n" : nil
        case Self.deleteKey:
            if chord == .command { return "\u{05}\u{15}" }  // ^E ^U — clear whole input line
            if chord == .option { return "\u{17}" }  // ^W — delete word backward
            return nil
        case Self.forwardDeleteKey:
            if chord == .command { return "\u{0B}" }  // ^K — delete to end of line
            if chord == .option { return "\u{1B}d" }  // ESC d — delete word forward
            return nil
        case Self.leftArrowKey:
            if chord == .command { return "\u{01}" }  // ^A — line start
            if chord == .option { return "\u{1B}b" }  // ESC b — word left
            return nil
        case Self.rightArrowKey:
            if chord == .command { return "\u{05}" }  // ^E — line end
            if chord == .option { return "\u{1B}f" }  // ESC f — word right
            return nil
        default:
            // Terminal.app's ⌘K clear idiom; claude redraws on ^L.
            if chord == .command, characters?.lowercased() == "k" { return "\u{0C}" }
            return nil
        }
    }

    static func sequence(for event: NSEvent) -> String? {
        sequence(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        )
    }
}
