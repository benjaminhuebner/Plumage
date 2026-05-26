import AppKit
import SwiftUI

// NSViewRepresentable wrapper around NSTextView. Renders `<slug>` / `<prompt>`
// / `<spec>` tokens in the bound string as chip-shaped NSTextAttachment cells.
// User edits serialize back to plain-text-with-`<tokens>` form so the binding
// stays a plain Swift String.
struct WorkflowCommandEditor: NSViewRepresentable {
    @Binding var text: String
    var onPlaceholderInsert: (WorkflowPlaceholder) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = true
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        context.coordinator.attach(textView: textView)
        context.coordinator.applyString(text, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Avoid clobbering the user's caret position on every keystroke.
        let serialized = WorkflowCommandSerialization.string(
            from: textView.attributedString()
        )
        if serialized != text {
            context.coordinator.applyString(text, to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private weak var textView: NSTextView?
        private var suppressNextChange = false

        init(text: Binding<String>) {
            self.text = text
        }

        func attach(textView: NSTextView) {
            self.textView = textView
        }

        func applyString(_ raw: String, to textView: NSTextView) {
            let attributed = WorkflowCommandSerialization.attributedString(from: raw)
            suppressNextChange = true
            textView.textStorage?.setAttributedString(attributed)
            suppressNextChange = false
        }

        func textDidChange(_ notification: Notification) {
            guard !suppressNextChange,
                let textView = notification.object as? NSTextView
            else { return }
            let serialized = WorkflowCommandSerialization.string(
                from: textView.attributedString()
            )
            if serialized != text.wrappedValue {
                text.wrappedValue = serialized
            }
        }

        // Plain-text copy: emit `<slug>` etc. so external paste shows tokens.
        func textView(
            _ textView: NSTextView,
            writablePasteboardTypesFor cell: any NSTextAttachmentCellProtocol,
            at charIndex: Int
        ) -> [NSPasteboard.PasteboardType] {
            [.string]
        }
    }
}
