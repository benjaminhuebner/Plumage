import SwiftUI

struct LabelChipEditor: View {
    let labels: [String]
    let existingLabels: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isEditing = false
    @State private var draft: String = ""
    @State private var showSuggestions = false
    @State private var matchesCache: [String] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // Index-keyed identity: an imported spec.md could carry duplicate
            // labels (the in-app commit path strips them via `isValid`, but
            // hand-edited frontmatter doesn't). `id: \.self` would collapse
            // duplicates to one ForEach row; positional IDs render them all.
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                LabelChip(text: label, onRemove: { onRemove(label) })
            }
            if isEditing {
                TextField("label", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($fieldFocused)
                    .onSubmit(commitDraft)
                    .onExitCommand { cancelDraft() }
                    .onChange(of: draft) { _, _ in refreshMatches() }
                    .onChange(of: existingLabels, initial: true) { _, _ in refreshMatches() }
                    .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                        suggestionList
                    }
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
            .accessibilityHint(isEditing ? "Commits the typed label" : "Shows the label input field")
            .disabled(
                isEditing
                    && Self.acceptedLabel(
                        draft: draft, existingLabels: existingLabels, currentLabels: labels) == nil
            )
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matchesCache, id: \.self) { label in
                Button {
                    accept(label)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(LabelColor.color(for: label))
                            .frame(width: 10, height: 10)
                        Text(label)
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 160, alignment: .leading)
        .padding(.vertical, 4)
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
        showSuggestions = false
    }

    private func accept(_ label: String) {
        onAdd(label)
        draft = ""
        isEditing = false
        fieldFocused = false
        showSuggestions = false
    }

    private func commitDraft() {
        guard
            let label = Self.acceptedLabel(
                draft: draft, existingLabels: existingLabels, currentLabels: labels)
        else {
            cancelDraft()
            return
        }
        accept(label)
    }

    private func refreshMatches() {
        matchesCache = Self.matches(for: draft, in: existingLabels)
        showSuggestions = isEditing && !matchesCache.isEmpty
    }

    // Prefer an existing label over a free-typed one so the color stays
    // consistent and prefix typos don't spawn near-duplicate labels.
    nonisolated static func acceptedLabel(
        draft: String, existingLabels: [String], currentLabels: [String]
    ) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        // Substitute only on an exact existing label (normalizes casing/dupes); a
        // prefix match stays a click-only suggestion, so "back" stays creatable
        // even when "backend" exists.
        if let exact = existingLabels.first(where: { $0.lowercased() == trimmed.lowercased() }) {
            return exact
        }
        guard isValid(trimmed), !currentLabels.contains(trimmed) else { return nil }
        return trimmed
    }

    nonisolated static func matches(for draft: String, in existingLabels: [String]) -> [String] {
        let needle = draft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return existingLabels.filter { $0.lowercased().hasPrefix(needle) }
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
            existingLabels: ["settings", "workflow", "ui", "backend"],
            onAdd: { newLabel in labels.wrappedValue.append(newLabel) },
            onRemove: { label in labels.wrappedValue.removeAll { $0 == label } }
        )
        .padding()
        .frame(width: 400)
    }
}
