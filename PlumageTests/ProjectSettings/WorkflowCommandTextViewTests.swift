import AppKit
import Foundation
import SwiftUI
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

    @Test("directive pills copy back as their literal text")
    func directiveCopyEmitsLiteral() {
        let textView = WorkflowCommandTextView()
        let original = "#if chore spike\n/quick\n#end"
        let attributed = WorkflowCommandSerialization.attributedString(from: original)
        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(NSRange(location: 0, length: attributed.length))

        let pboard = NSPasteboard.withUniqueName()
        let success = textView.writeSelection(to: pboard, types: [.string])

        #expect(success)
        #expect(pboard.string(forType: .string) == original)
    }
}

@MainActor
@Suite("WorkflowCommandEditor directive auto-conversion")
struct WorkflowCommandEditorDirectiveConversionTests {
    private func makeEditor(
        initial: String
    ) -> (textView: WorkflowCommandTextView, coordinator: WorkflowCommandEditor.Coordinator) {
        var text = initial
        let binding = Binding(get: { text }, set: { text = $0 })
        let coordinator = WorkflowCommandEditor.Coordinator(text: binding, catalog: .builtIn)
        let textView = WorkflowCommandTextView()
        coordinator.attach(textView: textView)
        textView.delegate = coordinator
        return (textView, coordinator)
    }

    private func directiveCells(in textView: NSTextView) -> [WorkflowCommandDirectiveCell] {
        var cells: [WorkflowCommandDirectiveCell] = []
        let attributed = textView.attributedString()
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if let attachment = value as? NSTextAttachment,
                let cell = attachment.attachmentCell as? WorkflowCommandDirectiveCell
            {
                cells.append(cell)
            }
        }
        return cells
    }

    @Test("a completed directive line converts once the caret leaves it")
    func convertsOffCaretLine() {
        let (textView, coordinator) = makeEditor(initial: "")
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: "#if chore\n/cmd")
        )
        // Caret on the second line — first line is eligible for conversion.
        textView.setSelectedRange(NSRange(location: 14, length: 0))
        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
        #expect(directiveCells(in: textView).count == 1)
        #expect(
            WorkflowCommandSerialization.string(from: textView.attributedString())
                == "#if chore\n/cmd"
        )
    }

    @Test("the caret's own line stays plain text while typing")
    func caretLineNotConverted() {
        let (textView, coordinator) = makeEditor(initial: "")
        let typed = "#if chore"
        textView.textStorage?.setAttributedString(NSAttributedString(string: typed))
        // Caret at end of the directive line, as after typing the last char.
        textView.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
        #expect(directiveCells(in: textView).isEmpty)
    }

    @Test("invalid directive lines never convert")
    func invalidDirectiveStaysPlain() {
        let (textView, coordinator) = makeEditor(initial: "")
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: "#if foobar\n/cmd")
        )
        textView.setSelectedRange(NSRange(location: 15, length: 0))
        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
        #expect(directiveCells(in: textView).isEmpty)
    }
}
