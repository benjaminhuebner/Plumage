import AppKit
import SwiftUI

// Inline TextField row for create-new-row interactions (set via
// `NavigatorModel.beginPendingCreate`).
struct InlineCreateRow: View {
    let projectURL: URL
    let icon: String
    @Environment(NavigatorModel.self) private var navigator
    @FocusState private var focused: Bool
    @State private var didAutoFocus = false
    @State private var isCommitting = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(
                "",
                text: nameBinding,
                prompt: Text(navigator.pendingCreate?.section.defaultName ?? "")
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand {
                navigator.cancelPendingCreate()
            }
            .onChange(of: focused) { _, isFocused in
                guard didAutoFocus, !isFocused else { return }
                commit()
            }
        }
        // Small delay so the row's TextField is part of the responder chain
        // before we ask for focus.
        .task(id: navigator.pendingCreate?.id) {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
            didAutoFocus = true
        }
    }

    private func commit() {
        // Guard both event paths (onSubmit + blur via onChange) so the second
        // trigger doesn't issue a redundant async task. `commitPendingCreate`
        // already short-circuits on a nil pending, but coalescing here keeps
        // the View layer authoritative on its own lifecycle.
        guard !isCommitting else { return }
        isCommitting = true
        Task { @MainActor in
            _ = await navigator.commitPendingCreate(projectURL: projectURL)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { navigator.pendingCreate?.name ?? "" },
            set: { newValue in
                guard navigator.pendingCreate != nil else { return }
                navigator.pendingCreate?.name = newValue
            }
        )
    }
}

// Inline rename row. Uses a custom NSViewRepresentable text field so the
// stem-selection (everything before the extension) is scoped to *this* view's
// field rather than reaching into `NSApp.keyWindow.firstResponder` — which
// races focus changes and silently picks the wrong window under multi-window
// scenarios.
struct InlineRenameRow: View {
    let projectURL: URL
    let icon: String
    @Environment(NavigatorModel.self) private var navigator
    @State private var isCommitting = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            StemSelectingTextField(
                text: nameBinding,
                placeholder: navigator.renaming?.url.lastPathComponent ?? "",
                onSubmit: commit,
                onCancel: { navigator.cancelRename() },
                onBlur: commit
            )
            .id(navigator.renaming?.id)
        }
    }

    private func commit() {
        guard !isCommitting else { return }
        isCommitting = true
        Task { @MainActor in
            _ = await navigator.commitRename(projectURL: projectURL)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { navigator.renaming?.name ?? "" },
            set: { newValue in
                guard navigator.renaming != nil else { return }
                navigator.renaming?.name = newValue
            }
        )
    }
}

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
        DispatchQueue.main.async { [weak field] in
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
