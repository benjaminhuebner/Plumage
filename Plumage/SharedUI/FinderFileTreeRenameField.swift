import AppKit
import SwiftUI

struct FinderFileTreeRenameField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    let onCancel: () -> Void

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
        // The field joins the window's responder chain only after the cell is
        // mounted — defer first-responder + stem selection one runloop tick.
        let coordinator = context.coordinator
        Task { @MainActor [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            coordinator.selectStem(in: field)
        }
        coordinator.installEscapeMonitor(for: field)
        return field
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeEscapeMonitor()
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FinderFileTreeRenameField
        private var hasFinished = false
        private var escapeMonitor: Any?

        init(_ parent: FinderFileTreeRenameField) {
            self.parent = parent
        }

        isolated deinit {
            removeEscapeMonitor()
        }

        // Defense-in-depth for Escape: if anything between sendEvent and the
        // field editor consumes it as a key equivalent, a later blur would
        // commit the typed text. The pre-dispatch monitor cancels first.
        func installEscapeMonitor(for field: NSTextField) {
            guard escapeMonitor == nil else { return }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self, weak field] event in
                guard let self, let field,
                    event.keyCode == 53,  // Escape
                    let editor = field.currentEditor(),
                    field.window?.firstResponder === editor
                else { return event }
                self.hasFinished = true
                self.parent.onCancel()
                return nil
            }
        }

        func removeEscapeMonitor() {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
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
                hasFinished = true
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                hasFinished = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        // Blur commits (the Finder idiom) — unless Return/Escape already
        // resolved the session.
        func controlTextDidEndEditing(_ obj: Notification) {
            guard !hasFinished else { return }
            parent.onCommit()
        }
    }
}
