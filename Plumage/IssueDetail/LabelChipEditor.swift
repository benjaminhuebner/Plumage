import SwiftUI

struct LabelChipEditor: View {
    let labels: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isEditing = false
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(labels, id: \.self) { label in
                LabelChip(text: label, onRemove: { onRemove(label) })
            }
            if isEditing {
                TextField("label", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($fieldFocused)
                    .onSubmit(commitDraft)
                    .onExitCommand { cancelDraft() }
            }
            Button {
                if isEditing {
                    commitDraft()
                } else {
                    startEditing()
                }
            } label: {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditing ? "Add label" : "Add new label")
            .disabled(isEditing && !LabelChipEditor.isValid(draft))
        }
    }

    private func startEditing() {
        draft = ""
        isEditing = true
        fieldFocused = true
    }

    private func cancelDraft() {
        draft = ""
        isEditing = false
        fieldFocused = false
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard LabelChipEditor.isValid(trimmed), !labels.contains(trimmed) else {
            cancelDraft()
            return
        }
        onAdd(trimmed)
        draft = ""
        isEditing = false
        fieldFocused = false
    }

    nonisolated static func isValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Reject characters that would corrupt the YAML flow-style array.
        let invalid: Set<Character> = [",", "[", "]"]
        if trimmed.contains(where: { invalid.contains($0) }) { return false }
        // Inner whitespace would also break the formatter's bare-scalar
        // assumption — the user can request it later by dropping the rule.
        if trimmed.contains(where: { $0.isWhitespace }) { return false }
        return true
    }
}

#Preview {
    StatefulPreviewWrapper(["feature", "ui"]) { labels in
        LabelChipEditor(
            labels: labels.wrappedValue,
            onAdd: { newLabel in labels.wrappedValue.append(newLabel) },
            onRemove: { label in labels.wrappedValue.removeAll { $0 == label } }
        )
        .padding()
        .frame(width: 400)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
