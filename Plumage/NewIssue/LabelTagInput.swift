import SwiftUI

nonisolated enum LabelTagInputLogic {
    static func commit(draft: inout String, into labels: inout [String]) {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        defer { draft = "" }
        guard !trimmed.isEmpty else { return }
        if !labels.contains(trimmed) {
            labels.append(trimmed)
        }
    }

    static func handleDraftChange(
        new: String,
        draft: inout String,
        labels: inout [String]
    ) {
        if new.contains(",") {
            let parts = new.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            for token in parts.dropLast() {
                var tmp = token
                commit(draft: &tmp, into: &labels)
            }
            draft = parts.last ?? ""
        } else {
            draft = new
        }
    }

    static func handleBackspaceOnEmptyDraft(draft: String, labels: inout [String]) {
        guard draft.isEmpty, !labels.isEmpty else { return }
        labels.removeLast()
    }
}

struct LabelTagInput: View {
    @Binding var labels: [String]
    @Binding var draft: String

    var body: some View {
        FlowLayout(spacing: 6) {
            // Labels are deduplicated on insert, so the value is a stable identity —
            // removing a middle pill diffs as a remove instead of a content shift.
            ForEach(labels, id: \.self) { label in
                LabelChip(text: label) {
                    labels.removeAll { $0 == label }
                }
            }
            TextField("Add label", text: $draft)
                .textFieldStyle(.plain)
                .frame(minWidth: 120)
                .onChange(of: draft) { _, newValue in
                    // Comma-trigger splits the draft into committed labels; non-comma
                    // edits already landed in `draft` via the binding above.
                    if newValue.contains(",") {
                        LabelTagInputLogic.handleDraftChange(
                            new: newValue, draft: &draft, labels: &labels)
                    }
                }
                .onSubmit {
                    LabelTagInputLogic.commit(draft: &draft, into: &labels)
                }
                .onKeyPress(.delete) {
                    if draft.isEmpty {
                        LabelTagInputLogic.handleBackspaceOnEmptyDraft(
                            draft: draft, labels: &labels)
                        return .handled
                    }
                    return .ignored
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
    }
}

#Preview {
    @Previewable @State var labels: [String] = ["feature", "v0.1", "bootstrap"]
    @Previewable @State var draft: String = ""
    LabelTagInput(labels: $labels, draft: $draft)
        .padding()
        .frame(width: 360)
}
