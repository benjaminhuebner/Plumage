import AppKit
import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("WorkflowCommandTextView copy/paste")
struct WorkflowCommandTextViewTests {
    @Test("writeSelection emits placeholder tokens as plain text")
    func writeSelectionEmitsTokens() {
        let textView = WorkflowCommandTextView()
        let attributed = WorkflowCommandSerialization.attributedString(
            from: "/cmd <slug>\n<prompt>"
        )
        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(NSRange(location: 0, length: attributed.length))

        let pboard = NSPasteboard.withUniqueName()
        let success = textView.writeSelection(to: pboard, types: [.string])

        #expect(success)
        #expect(pboard.string(forType: .string) == "/cmd <slug>\n<prompt>")
    }

    @Test("writablePasteboardTypes restricted to .string")
    func writablePasteboardTypes() {
        let textView = WorkflowCommandTextView()
        #expect(textView.writablePasteboardTypes == [.string])
    }
}
