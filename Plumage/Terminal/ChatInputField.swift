import SwiftUI

struct ChatInputField: View {
    @Binding var text: String
    let canSend: Bool
    let onSend: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 36, maxHeight: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send (⌘↩)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

#Preview("Disabled (awaiting response)") {
    StatefulPreview(initialText: "I'm waiting…") { binding in
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
