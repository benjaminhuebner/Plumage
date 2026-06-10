import AppKit
import SwiftUI

// AppKit-backed text field for inline rename. Owns its own focus + stem
// selection so we don't need a 50 ms sleep + NSApp.keyWindow reach.
struct StemSelectingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onBlur: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        // Defer becomeFirstResponder + selectStem to the next runloop tick so
        // the field is part of the window's responder chain by the time we
        // ask. Scoped to this field instance — no global firstResponder reach.
        let coord = context.coordinator
        Task { @MainActor [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            coord.selectStem(in: field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: StemSelectingTextField
        private var hasSubmitted = false

        init(_ parent: StemSelectingTextField) {
            self.parent = parent
        }

        func selectStem(in field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let raw = field.stringValue as NSString
            let dot = raw.range(of: ".", options: .backwards)
            let range: NSRange
            if dot.location == NSNotFound || dot.location == 0 {
                range = NSRange(location: 0, length: raw.length)
            } else {
                range = NSRange(location: 0, length: dot.location)
            }
            editor.selectedRange = range
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                hasSubmitted = true
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                hasSubmitted = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !hasSubmitted else { return }
            parent.onBlur()
        }
    }
}
