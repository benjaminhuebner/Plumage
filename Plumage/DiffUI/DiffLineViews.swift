import LanguageSupport
import SwiftUI

// Shared diff line/hunk rendering for DiffTabView (issue diff) and
// GitCommitView (staged diff) — the two per-feature copies had drifted.

nonisolated struct DiffLineStyle: Equatable {
    let font: Font
    let textStyle: Font.TextStyle
    let horizontalPadding: CGFloat
    let showsLineNumbers: Bool

    static let detail = DiffLineStyle(
        font: .system(.body, design: .monospaced), textStyle: .body, horizontalPadding: 12,
        showsLineNumbers: true)
    static let compact = DiffLineStyle(
        font: .system(.caption, design: .monospaced), textStyle: .caption, horizontalPadding: 0,
        showsLineNumbers: false)

    // Side-by-side panes force this height on every row: two independent
    // lazy stacks stay vertically aligned only if row heights never depend
    // on content (emoji fallback fonts grow a Text's natural line height).
    @MainActor var uniformRowHeight: CGFloat {
        let base = NSFont.preferredFont(forTextStyle: nsTextStyle)
        let descriptor = base.fontDescriptor.withDesign(.monospaced) ?? base.fontDescriptor
        let mono = NSFont(descriptor: descriptor, size: 0) ?? base
        return (mono.ascender - mono.descender + mono.leading).rounded(.up) + 2
    }

    private var nsTextStyle: NSFont.TextStyle {
        switch textStyle {
        case .caption: return .caption1
        default: return .body
        }
    }
}

// Equatable container for one hunk's lines: Hunk is a value, replaced
// wholesale on reload, so `.equatable()` lets SwiftUI skip untouched hunks
// entirely — the per-line AttributedString below is the expensive part.
struct DiffHunkLinesView: View, Equatable {
    let hunk: Hunk
    let style: DiffLineStyle
    var commenting: DiffCommenting?

    init(hunk: Hunk, style: DiffLineStyle, commenting: DiffCommenting? = nil) {
        self.hunk = hunk
        self.style = style
        self.commenting = commenting
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hunk == rhs.hunk && lhs.style == rhs.style
            && DiffCommenting.isSame(lhs.commenting, rhs.commenting)
    }

    var body: some View {
        let numbers = style.showsLineNumbers ? DiffLineNumber.numbers(for: hunk) : []
        let digits = DiffLineNumber.columnDigits(for: hunk)
        LazyVStack(alignment: .leading, spacing: 0) {
            // Index identity is safe here: lines never reorder in place —
            // a changed hunk is a different Hunk value with fresh rows.
            if let commenting {
                let anchors = DiffLineAnchor.anchors(for: hunk, file: commenting.file)
                ForEach(hunk.lines.indices, id: \.self) { index in
                    CommentableDiffLineRow(
                        line: hunk.lines[index],
                        style: style,
                        anchor: anchors[index],
                        model: commenting.model,
                        numbers: numbers.isEmpty ? nil : numbers[index],
                        numberColumnDigits: digits
                    )
                    .id(anchors[index])
                    if hunk.lines[index].hasNoTrailingNewline {
                        DiffNoNewlineMarker(style: style)
                    }
                }
            } else {
                ForEach(hunk.lines.indices, id: \.self) { index in
                    DiffLineRow(
                        line: hunk.lines[index], style: style,
                        numbers: numbers.isEmpty ? nil : numbers[index],
                        numberColumnDigits: digits
                    )
                    .equatable()
                    if hunk.lines[index].hasNoTrailingNewline {
                        DiffNoNewlineMarker(style: style)
                    }
                }
            }
        }
    }
}

struct DiffLineRow: View, Equatable {
    let line: Line
    let style: DiffLineStyle
    var numbers: DiffLineNumber?
    var numberColumnDigits: Int

    init(
        line: Line, style: DiffLineStyle,
        numbers: DiffLineNumber? = nil, numberColumnDigits: Int = 0
    ) {
        self.line = line
        self.style = style
        self.numbers = numbers
        self.numberColumnDigits = numberColumnDigits
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if style.showsLineNumbers, numbers != nil {
                Text(numberColumnsText)
                    .font(style.font)
                    .foregroundStyle(.tertiary)
            }
            Text(line.kind.diffSymbol)
                .font(style.font)
                .foregroundStyle(line.kind.diffSymbolColor)
                .frame(width: 14, alignment: .leading)
            tokenizedText
                .font(style.font)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, 1)
        .background(line.kind.diffRowTint)
    }

    // Monospaced space-padding keeps both number columns aligned without
    // any measured widths.
    private var numberColumnsText: String {
        let width = max(numberColumnDigits, 1)
        let old = numbers?.old.map(String.init) ?? ""
        let new = numbers?.new.map(String.init) ?? ""
        return pad(old, to: width) + " " + pad(new, to: width)
    }

    private func pad(_ value: String, to width: Int) -> String {
        String(repeating: " ", count: max(width - value.count, 0)) + value
    }

    private var tokenizedText: Text {
        DiffLineText.styledText(for: line)
    }
}

nonisolated enum DiffLineText {
    static func styledText(for line: Line) -> Text {
        let wordRanges = line.changedRanges ?? []
        guard !line.tokens.isEmpty || !wordRanges.isEmpty else {
            return Text(line.content)
        }
        var attributed = AttributedString(line.content)
        for token in line.tokens {
            guard let range = attributedRange(for: token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = color(for: token.kind)
        }
        if let wordTint = wordTint(for: line.kind) {
            for changed in wordRanges {
                guard let range = attributedRange(for: changed, in: attributed) else { continue }
                attributed[range].backgroundColor = wordTint
            }
        }
        return Text(attributed)
    }

    private static func attributedRange(
        for range: Range<String.Index>,
        in attributed: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard
            let lower = AttributedString.Index(range.lowerBound, within: attributed),
            let upper = AttributedString.Index(range.upperBound, within: attributed)
        else { return nil }
        return lower..<upper
    }

    private static func wordTint(for kind: LineKind) -> Color? {
        switch kind {
        case .added: return Color.green.opacity(0.28)
        case .removed: return Color.red.opacity(0.28)
        case .context: return nil
        }
    }

    static func color(for kind: LanguageConfiguration.Token) -> Color {
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
