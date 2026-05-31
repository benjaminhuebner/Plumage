import AppKit
import SwiftUI

struct ChatInputField: View {
    @Binding var text: String
    let canSend: Bool
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @State private var contentHeight: CGFloat = 22
    @State private var isDropTargeted = false

    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 132

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            inputBubble
            sendButton
                .alignmentGuide(.bottom) { dim in dim.height + 4 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                contentHeight = minHeight
            }
        }
    }

    @ViewBuilder
    private var inputBubble: some View {
        ZStack(alignment: .topLeading) {
            SubmittingTextEditor(
                text: $text,
                contentHeight: $contentHeight,
                onSubmit: sendIfAllowed
            )
            .frame(height: clampedHeight)
            .focused($focused)

            if text.isEmpty {
                Text("Message claude…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        // NSTextView renders glyphs flush to the top of its frame; balance the
        // bubble's vertical padding so single-line text reads visually centred
        // (text glyph height ≈ 13pt vs. editor frame ≈ 22pt leaves ~9pt to
        // distribute; weighting more above shifts the glyphs to the middle).
        .padding(.top, 11)
        .padding(.bottom, 5)
        .background(.background.tertiary, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    focused || isDropTargeted
                        ? Color.accentColor.opacity(0.45)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            appendDroppedPaths(files)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
    }

    private func appendDroppedPaths(_ urls: [URL]) {
        let insertion = DroppedFilePaths.insertionText(for: urls)
        guard !insertion.isEmpty else { return }
        // Preserve whatever the user already typed; add a separating space only
        // when the draft doesn't already end with whitespace.
        if text.isEmpty || text.last?.isWhitespace == true {
            text += insertion
        } else {
            text += " " + insertion
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: sendIfAllowed) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!isReady)
        .opacity(isReady ? 1 : 0.45)
        .animation(.snappy(duration: 0.12), value: isReady)
        .help("Send (⏎ — Shift+⏎ for newline)")
        .accessibilityLabel("Send message")
    }

    private var buttonFill: AnyShapeStyle {
        isReady
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color.secondary.opacity(0.35))
    }

    private var clampedHeight: CGFloat {
        min(max(contentHeight, minHeight), maxHeight)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isReady: Bool {
        canSend && !trimmed.isEmpty
    }

    private func sendIfAllowed() {
        guard isReady else { return }
        onSend()
    }
}

private struct SubmittingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.font = .preferredFont(forTextStyle: .callout)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? SubmittingTextView else { return }
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.measureHeight(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $contentHeight)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let textBinding: Binding<String>
        let heightBinding: Binding<CGFloat>

        init(text: Binding<String>, height: Binding<CGFloat>) {
            self.textBinding = text
            self.heightBinding = height
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textBinding.wrappedValue != textView.string {
                textBinding.wrappedValue = textView.string
            }
            measureHeight(textView)
        }

        func measureHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let newHeight = ceil(used.height)
            guard abs(heightBinding.wrappedValue - newHeight) > 0.5 else { return }
            // Coordinator.measureHeight runs from updateNSView, which is
            // inside SwiftUI's view-update cycle; writing the binding here
            // synchronously triggers "Modifying state during view update".
            // Defer to the next runloop tick — Task hop keeps everything
            // inside the @MainActor model instead of dropping to GCD.
            let binding = heightBinding
            Task { @MainActor in
                binding.wrappedValue = newHeight
            }
        }
    }
}

private final class SubmittingTextView: NSTextView {
    var onSubmit: (() -> Void)?

    // NSTextView greedily registers .fileURL and inserts a dropped file's
    // *contents* on drop, which would steal the Finder drop from the SwiftUI
    // .dropDestination behind it. Registering only .string here keeps text
    // drag-in while letting file-URL drags bubble up to the drop destination
    // that inserts the path text instead.
    override func updateDragTypeRegistration() {
        registerForDraggedTypes([.string])
    }

    override func keyDown(with event: NSEvent) {
        // Return = keyCode 36, Enter on numpad = keyCode 76.
        // Plain (no shift) submits; with shift falls through to default — insert newline.
        if (event.keyCode == 36 || event.keyCode == 76)
            && !event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.option)
        {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

#Preview("Empty") {
    StatefulPreview(initialText: "") { binding in
        ChatInputField(text: binding, canSend: true, onSend: {})
            .frame(width: 460)
    }
}

#Preview("With text") {
    StatefulPreview(initialText: "What does this codebase do?") { binding in
        ChatInputField(text: binding, canSend: true, onSend: {})
            .frame(width: 460)
    }
}

#Preview("Multiline") {
    StatefulPreview(initialText: "line one\nline two\nline three") { binding in
        ChatInputField(text: binding, canSend: true, onSend: {})
            .frame(width: 460)
    }
}

#Preview("Disabled") {
    StatefulPreview(initialText: "queued") { binding in
        ChatInputField(text: binding, canSend: false, onSend: {})
            .frame(width: 460)
    }
}

private struct StatefulPreview<Content: View>: View {
    @State var text: String
    let content: (Binding<String>) -> Content

    init(initialText: String, @ViewBuilder content: @escaping (Binding<String>) -> Content) {
        self._text = State(initialValue: initialText)
        self.content = content
    }

    var body: some View {
        content($text)
    }
}
