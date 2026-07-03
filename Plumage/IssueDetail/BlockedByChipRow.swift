import SwiftUI

nonisolated struct BlockerCandidate: Hashable, Sendable {
    let folderName: String
    let id: Int
    let title: String
}

struct BlockedByChipRow: View {
    let blockers: [ResolvedBlocker]
    let candidates: [BlockerCandidate]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    let onOpen: (String) -> Void

    @State private var isEditing = false
    @State private var draft: String = ""
    @State private var showSuggestions = false
    @State private var matchesCache: [BlockerCandidate] = []
    @FocusState private var fieldFocused: Bool

    private var hasOpenBlockers: Bool {
        blockers.contains { $0.state == .open }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "lock")
                    .imageScale(.small)
                    .foregroundStyle(
                        hasOpenBlockers ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)
                    )
                Text("Blocked by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            ForEach(blockers, id: \.folderName) { blocker in
                chip(for: blocker)
            }
            if isEditing {
                TextField("id or title", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($fieldFocused)
                    .onSubmit(commitDraft)
                    .onExitCommand { cancelDraft() }
                    .onChange(of: draft) { _, _ in refreshMatches() }
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
            .accessibilityLabel(isEditing ? "Add blocker" : "Add new blocker")
            .accessibilityHint(
                isEditing ? "Adds the selected blocking issue" : "Shows the blocker search field"
            )
            .disabled(isEditing && acceptedCandidate() == nil)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chip(for blocker: ResolvedBlocker) -> some View {
        HStack(spacing: 4) {
            Button {
                onOpen(blocker.folderName)
            } label: {
                Text(chipText(for: blocker))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(blocker.state == .missing ? .secondary : .primary)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .disabled(blocker.state == .missing)
            .accessibilityLabel("Open blocking issue \(chipText(for: blocker))")
            Button {
                onRemove(blocker.folderName)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove blocker \(blocker.folderName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            blocker.state == .open
                ? AnyShapeStyle(Color.red.opacity(0.16))
                : AnyShapeStyle(Color(NSColor.tertiarySystemFill)),
            in: Capsule()
        )
        .opacity(blocker.state == .missing ? 0.6 : 1)
        .help(helpText(for: blocker))
    }

    private func chipText(for blocker: ResolvedBlocker) -> String {
        guard let id = blocker.id, let title = blocker.title else {
            return blocker.folderName
        }
        return "#\(IssueIDFormatter.padded(id, width: 5)) \(title)"
    }

    private func helpText(for blocker: ResolvedBlocker) -> String {
        switch blocker.state {
        case .missing: "No issue with this folder name on the board — remove the stale entry."
        case .done: "Done — no longer blocking."
        case .open: "Still open."
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matchesCache, id: \.folderName) { candidate in
                Button {
                    accept(candidate)
                } label: {
                    HStack(spacing: 6) {
                        Text("#\(IssueIDFormatter.padded(candidate.id, width: 5))")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        Text(candidate.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 240, alignment: .leading)
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

    private func accept(_ candidate: BlockerCandidate) {
        onAdd(candidate.folderName)
        cancelDraft()
    }

    private func commitDraft() {
        guard let candidate = acceptedCandidate() else {
            cancelDraft()
            return
        }
        accept(candidate)
    }

    private func acceptedCandidate() -> BlockerCandidate? {
        matchesCache.count == 1 ? matchesCache.first : nil
    }

    private func refreshMatches() {
        matchesCache = Self.matches(
            for: draft,
            in: candidates,
            excluding: Set(blockers.map(\.folderName))
        )
        showSuggestions = isEditing && !matchesCache.isEmpty
    }

    nonisolated static func matches(
        for draft: String,
        in candidates: [BlockerCandidate],
        excluding current: Set<String>
    ) -> [BlockerCandidate] {
        let needle = draft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        let idNeedle = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
        return
            candidates
            .filter { !current.contains($0.folderName) }
            .filter { candidate in
                if IssueIDFormatter.padded(candidate.id, width: 5).contains(idNeedle) { return true }
                return candidate.title.lowercased().contains(needle)
            }
            .prefix(8)
            .map { $0 }
    }
}

#Preview {
    BlockedByChipRow(
        blockers: [
            ResolvedBlocker(folderName: "00042-auth", state: .open, id: 42, title: "User auth"),
            ResolvedBlocker(folderName: "00007-old", state: .done, id: 7, title: "Old groundwork"),
            ResolvedBlocker(folderName: "00099-gone", state: .missing, id: nil, title: nil),
        ],
        candidates: [
            BlockerCandidate(folderName: "00010-a", id: 10, title: "Board polish"),
            BlockerCandidate(folderName: "00011-b", id: 11, title: "Editor tabs"),
        ],
        onAdd: { _ in },
        onRemove: { _ in },
        onOpen: { _ in }
    )
    .padding()
    .frame(width: 700)
}
