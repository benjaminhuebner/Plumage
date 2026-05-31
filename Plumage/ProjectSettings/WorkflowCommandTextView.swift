import AppKit

// The two overrides make placeholder chips copy and drag out as their plain
// `<slug>` tokens — `writeSelection(to:types:)` for Cmd-C, the drag-out path
// for dropping a chip into Finder/Notes. Without them AppKit writes
// attachment-archive bytes instead of text.
final class WorkflowCommandTextView: NSTextView {
    override func writeSelection(
        to pboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        guard types.contains(.string) || types.contains(.tabularText) else {
            return super.writeSelection(to: pboard, types: types)
        }
        let selection = attributedSubstring(forProposedRange: selectedRange(), actualRange: nil)
        guard let selection else {
            return super.writeSelection(to: pboard, types: types)
        }
        let plain = WorkflowCommandSerialization.string(from: selection)
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(plain, forType: .string)
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        // Force the textView's default Cmd-C path to ask for `.string` so our
        // writeSelection override gets the call. Without this, NSTextView may
        // also offer RTF/RTFD types which Cmd-C prefers when present.
        [.string]
    }
}
