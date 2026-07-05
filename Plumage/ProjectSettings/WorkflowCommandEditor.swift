import AppKit
import SwiftUI

// NSViewRepresentable wrapper around NSTextView. Renders `<slug>` / `<prompt>`
// / `<spec>` tokens in the bound string as chip-shaped NSTextAttachment cells.
// User edits serialize back to plain-text-with-`<tokens>` form so the binding
// stays a plain Swift String.
struct WorkflowCommandEditor: NSViewRepresentable {
    @Binding var text: String
    var catalog: IssueTypeCatalog = .builtIn
    var onPlaceholderInsert: (WorkflowPlaceholder) -> Void = { _ in }

    static let minHeight: CGFloat = 90

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
        let catalogChanged = context.coordinator.catalog != catalog
        context.coordinator.catalog = catalog
        // Avoid clobbering the user's caret position on every keystroke.
        let serialized = WorkflowCommandSerialization.string(
            from: textView.attributedString()
        )
        if serialized != text || catalogChanged {
            context.coordinator.applyString(text, to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, catalog: catalog)
    }

    // Grows the editor with its content instead of scrolling. Measured against
    // the proposed width so wrap-induced height changes land in the same
    // layout pass; the text binding updates on every keystroke, re-running this.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSScrollView, context: Context
    ) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return nil }
        if let width = proposal.width, width.isFinite, width > 0 {
            container.containerSize = NSSize(
                width: width, height: CGFloat.greatestFiniteMagnitude
            )
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = max(
            Self.minHeight, ceil(used.height + textView.textContainerInset.height * 2)
        )
        return CGSize(width: proposal.width ?? used.width, height: height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private weak var textView: NSTextView?
        private var suppressNextChange = false
        var catalog: IssueTypeCatalog

        init(text: Binding<String>, catalog: IssueTypeCatalog) {
            self.text = text
            self.catalog = catalog
        }

        func attach(textView: NSTextView) {
            self.textView = textView
        }

        func applyString(_ raw: String, to textView: NSTextView) {
            let attributed = WorkflowCommandSerialization.attributedString(
                from: raw, catalog: catalog
            )
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
            autoConvertDirectives(in: storage, textView: textView)
            restyleCommandTokens(in: storage)
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

        // Directives have no closing terminator like the placeholders' `>`,
        // so the caret's line is left alone — converting mid-typing would
        // freeze the pill under the user's fingers; leaving the line converts.
        private func autoConvertDirectives(
            in storage: NSTextStorage, textView: NSTextView
        ) {
            let plain = storage.string
            let nsPlain = plain as NSString
            let fullRange = NSRange(location: 0, length: nsPlain.length)
            let matches = WorkflowCommandSerialization.directivePattern
                .matches(in: plain, options: [], range: fullRange)
            guard !matches.isEmpty else { return }

            let selection = textView.selectedRange()
            suppressNextChange = true
            defer { suppressNextChange = false }

            storage.beginEditing()
            var converted = false
            for match in matches.reversed() {
                var lineStart = 0
                var contentsEnd = 0
                nsPlain.getLineStart(
                    &lineStart, end: nil, contentsEnd: &contentsEnd, for: match.range
                )
                if selection.location >= lineStart, selection.location <= contentsEnd {
                    continue
                }
                let textRange = match.range(at: 1)
                let text = nsPlain.substring(with: textRange)
                guard
                    let kind = WorkflowCommandSerialization.directiveKind(
                        for: text, catalog: catalog
                    )
                else {
                    continue
                }
                let attachment = NSTextAttachment()
                attachment.attachmentCell = WorkflowCommandDirectiveCell(
                    kind: kind, rawText: text, catalog: catalog
                )
                storage.replaceCharacters(
                    in: textRange, with: NSAttributedString(attachment: attachment)
                )
                converted = true
            }
            storage.endEditing()
            guard converted else { return }

            let newLength = textView.attributedString().length
            let clamped = min(selection.location, newLength)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }

        // Attribute-only pass — no text mutation, so the caret stays put.
        private func restyleCommandTokens(in storage: NSTextStorage) {
            suppressNextChange = true
            defer { suppressNextChange = false }
            storage.beginEditing()
            WorkflowCommandSerialization.applyCommandHighlighting(to: storage)
            storage.endEditing()
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
