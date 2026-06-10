import LanguageSupport
import SwiftUI

// Shared diff line/hunk rendering for DiffTabView (issue diff) and
// GitCommitView (staged diff) — the two per-feature copies had already
// drifted apart (#00087 audit).

nonisolated struct DiffLineStyle: Equatable {
    let font: Font
    let horizontalPadding: CGFloat

    static let detail = DiffLineStyle(
        font: .system(.body, design: .monospaced), horizontalPadding: 12)
    static let compact = DiffLineStyle(
        font: .system(.caption, design: .monospaced), horizontalPadding: 0)
}

// Equatable container for one hunk's lines: Hunk is a value, replaced
// wholesale on reload, so `.equatable()` lets SwiftUI skip untouched hunks
// entirely — the per-line AttributedString below is the expensive part.
struct DiffHunkLinesView: View, Equatable {
    let hunk: Hunk
    let style: DiffLineStyle

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // Index identity is safe here: lines never reorder in place —
            // a changed hunk is a different Hunk value with fresh rows.
            ForEach(hunk.lines.indices, id: \.self) { index in
                DiffLineRow(line: hunk.lines[index], style: style)
                    .equatable()
            }
        }
    }
}

struct DiffLineRow: View, Equatable {
    let line: Line
    let style: DiffLineStyle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(symbol)
                .font(style.font)
                .foregroundStyle(symbolColor)
                .frame(width: 14, alignment: .leading)
            tokenizedText
                .font(style.font)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, style.horizontalPadding)
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
            attributed[lower..<upper].foregroundColor = Self.color(for: token.kind)
        }
        return Text(attributed)
    }

    private static func color(for kind: LanguageConfiguration.Token) -> Color {
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
