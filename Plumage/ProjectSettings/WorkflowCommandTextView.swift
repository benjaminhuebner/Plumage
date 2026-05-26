import AppKit

// NSTextView subclass for the workflow command editor. Two overrides:
// (a) `writeSelection(to:types:)` ensures that Cmd-C on a selection containing
//     placeholder chips writes the placeholder tokens (`<slug>` etc.) as plain
//     text on the pasteboard, not attachment-archive garbage; (b) the same
//     conversion applies to any drag-out, so dragging a chip into Finder/Notes
//     yields `<slug>`-style text.
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
