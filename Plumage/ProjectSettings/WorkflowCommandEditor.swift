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
        let textView = WorkflowCommandTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
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
                let textView = notification.object as? NSTextView,
                let storage = textView.textStorage
            else { return }
            autoConvertPlaceholders(in: storage, textView: textView)
            let serialized = WorkflowCommandSerialization.string(
                from: textView.attributedString()
            )
            if serialized != text.wrappedValue {
                text.wrappedValue = serialized
            }
        }

        // Scan the text storage for plain-text `<slug>`/`<prompt>`/`<spec>`
        // matches and swap each one for an attachment chip in-place. Runs
        // after every keystroke so the moment a user finishes typing `>`
        // the token instantly becomes a pill. Attachments in the storage
        // already serialize their character to U+FFFC, so the regex never
        // re-matches existing chips.
        private func autoConvertPlaceholders(
            in storage: NSTextStorage, textView: NSTextView
        ) {
            let plain = storage.string
            let fullRange = NSRange(location: 0, length: (plain as NSString).length)
            let matches = WorkflowCommandSerialization.placeholderPattern
                .matches(in: plain, options: [], range: fullRange)
            guard !matches.isEmpty else { return }

            let originalSelection = textView.selectedRange()
            suppressNextChange = true
            defer { suppressNextChange = false }

            storage.beginEditing()
            // Replace from the end so earlier ranges don't shift as we mutate.
            for match in matches.reversed() {
                let tokenRange = match.range(at: 1)
                let token = (plain as NSString).substring(with: tokenRange)
                guard let placeholder = WorkflowPlaceholder(rawValue: token) else {
                    continue
                }
                let cell = WorkflowCommandPlaceholderCell(placeholder: placeholder)
                let attachment = NSTextAttachment()
                attachment.attachmentCell = cell
                let replacement = NSAttributedString(attachment: attachment)
                storage.replaceCharacters(in: match.range, with: replacement)
            }
            storage.endEditing()

            // Place the caret immediately after the right-most inserted chip
            // if the original caret sat at or past that boundary; otherwise
            // clamp to the new total length. Without this, mass-replacement
            // can drop the caret somewhere unintuitive (e.g. at start).
            let newLength = textView.attributedString().length
            let clamped = min(originalSelection.location, newLength)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
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
