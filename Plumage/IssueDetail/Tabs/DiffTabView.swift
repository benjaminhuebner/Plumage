import LanguageSupport
import SwiftUI

struct DiffTabView: View {
    @Bindable var model: DiffTabModel

    var body: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        case .empty:
            emptyState
        case .diff(let files):
            diffList(files)
        case .error(let error):
            errorState(error)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        BodyTabEmptyState(
            symbol: "checkmark.diamond",
            title: "Keine Änderungen auf diesem Branch",
            detail: "Committe etwas, um den Diff zu sehen."
        )
    }

    @ViewBuilder
    private func errorState(_ error: GitDiffError) -> some View {
        BodyTabEmptyState(
            symbol: "exclamationmark.triangle",
            title: "Diff konnte nicht geladen werden",
            detail: error.displayMessage
        )
    }

    @ViewBuilder
    private func diffList(_ files: [FileDiff]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // id by path so FileDiffSection's @State (isExpanded) tracks
                // the file, not its position in the list. Without this a
                // reorder or insertion would silently transfer the user's
                // collapse state to a different file.
                ForEach(files, id: \.path) { file in
                    FileDiffSection(file: file)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(minHeight: 240)
    }
}

private struct FileDiffSection: View {
    let file: FileDiff
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { offset, hunk in
                    if offset > 0 {
                        HunkSeparator()
                    }
                    HunkView(hunk: hunk)
                }
            }
            .padding(.top, 4)
        } label: {
            FileDiffHeader(file: file)
        }
    }
}

private struct FileDiffHeader: View {
    let file: FileDiff

    var body: some View {
        HStack(spacing: 10) {
            statusBadge
            Text(file.path)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            additionsRemovals
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(badgeText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeText: String {
        switch file.status {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .binary: return "Binary"
        case .submodule: return "Submodule"
        }
    }

    private var badgeColor: Color {
        switch file.status {
        case .added: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .renamed: return .orange
        case .copied: return .orange
        case .binary: return .gray
        case .submodule: return .purple
        }
    }

    @ViewBuilder
    private var additionsRemovals: some View {
        let counts = file.hunks.reduce(into: (added: 0, removed: 0)) { acc, hunk in
            for line in hunk.lines {
                switch line.kind {
                case .added: acc.added += 1
                case .removed: acc.removed += 1
                case .context: break
                }
            }
        }
        HStack(spacing: 6) {
            Text("+\(counts.added)")
                .foregroundStyle(.green)
            Text("−\(counts.removed)")
                .foregroundStyle(.red)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct HunkSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 1)
    }
}

private struct HunkView: View {
    let hunk: Hunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hunkHeader
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                LineRow(line: line)
            }
        }
    }

    @ViewBuilder
    private var hunkHeader: some View {
        HStack(spacing: 6) {
            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if !hunk.headerContext.isEmpty {
                Text(hunk.headerContext)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LineRow: View {
    let line: Line

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(symbol)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(symbolColor)
                .frame(width: 14, alignment: .leading)
            tokenizedText
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(rowTint)
    }

    private var symbol: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private var symbolColor: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var rowTint: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .context: return Color.clear
        }
    }

    private var tokenizedText: Text {
        guard !line.tokens.isEmpty else {
            return Text(line.content)
        }
        var attributed = AttributedString(line.content)
        for token in line.tokens {
            guard
                let lower = AttributedString.Index(token.range.lowerBound, within: attributed),
                let upper = AttributedString.Index(token.range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].foregroundColor = color(for: token.kind)
        }
        return Text(attributed)
    }

    private func color(for kind: LanguageConfiguration.Token) -> Color {
        switch kind {
        case .keyword: return .purple
        case .string, .character: return .red
        case .number: return .blue
        case .singleLineComment, .nestedCommentOpen, .nestedCommentClose: return .secondary
        case .identifier(let flavour):
            guard let flavour else { return .primary }
            switch flavour {
            case .type, .typeParameter: return .teal
            case .function, .method: return .indigo
            case .macro: return .pink
            default: return .primary
            }
        case .operator: return .orange
        case .regexp: return .red
        case .symbol: return .primary
        case .roundBracketOpen, .roundBracketClose,
            .squareBracketOpen, .squareBracketClose,
            .curlyBracketOpen, .curlyBracketClose:
            return .secondary
        }
    }
}
