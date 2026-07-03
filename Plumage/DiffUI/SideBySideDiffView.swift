import SwiftUI

struct SideBySideHunkView: View, Equatable {
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
        let rows = SideBySideLayout.rows(for: hunk)
        let digits = SideBySideLayout.columnDigits(for: hunk)
        if let commenting {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(segments(rows: rows, commenting: commenting)) { segment in
                    panePair(
                        rows: rows, range: segment.range, digits: digits, commenting: commenting)
                    ForEach(segment.anchors, id: \.self) { anchor in
                        commentBlock(anchor: anchor, model: commenting.model)
                    }
                }
            }
        } else {
            panePair(rows: rows, range: rows.indices, digits: digits, commenting: nil)
        }
    }

    private func panePair(
        rows: [SideBySideRow],
        range: Range<Int>,
        digits: (old: Int, new: Int),
        commenting: DiffCommenting?
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SideBySidePane(
                rows: rows, range: range, side: .old, style: style, digits: digits.old,
                commenting: commenting)
            Divider()
            SideBySidePane(
                rows: rows, range: range, side: .new, style: style, digits: digits.new,
                commenting: commenting)
        }
    }

    @ViewBuilder
    private func commentBlock(anchor: DiffLineAnchor, model: ReviewFindingsModel) -> some View {
        ForEach(model.findings(at: anchor).filter { $0.id != model.draft?.editingID }) { finding in
            DiffCommentRow(finding: finding, model: model)
        }
        if let draft = model.draft, draft.anchor == anchor {
            DiffCommentEditor(model: model)
        }
    }

    private struct Segment: Identifiable {
        let range: Range<Int>
        let anchors: [DiffLineAnchor]

        var id: Int { range.lowerBound }
    }

    // A hunk splits after every row that carries findings or the active
    // draft, so comment blocks render full-width between the pane pairs
    // instead of inside a horizontal scroller.
    private func segments(rows: [SideBySideRow], commenting: DiffCommenting) -> [Segment] {
        var segments: [Segment] = []
        var start = 0
        for index in rows.indices {
            let anchors = DiffLineAnchor.anchors(for: rows[index], file: commenting.file)
            var rowAnchors: [DiffLineAnchor] = []
            for anchor in [anchors.old, anchors.new].compactMap({ $0 })
            where !rowAnchors.contains(anchor) {
                rowAnchors.append(anchor)
            }
            let active = rowAnchors.filter { anchor in
                !commenting.model.findings(at: anchor).isEmpty
                    || commenting.model.draft?.anchor == anchor
            }
            if !active.isEmpty {
                segments.append(Segment(range: start..<(index + 1), anchors: active))
                start = index + 1
            }
        }
        if start < rows.count || segments.isEmpty {
            segments.append(Segment(range: start..<rows.count, anchors: []))
        }
        return segments
    }
}

private struct SideBySidePane: View {
    let rows: [SideBySideRow]
    let range: Range<Int>
    let side: SideBySideAnchorSide
    let style: DiffLineStyle
    let digits: Int
    var commenting: DiffCommenting?

    @State private var hoveredRow: Int?

    // A vertical lazy stack inside a horizontal scroller gets the viewport
    // width proposed and truncates rows — hence plain VStack; the tint
    // stripes sit behind the scroller so they span the pane, not the text.
    var body: some View {
        let rowHeight = style.uniformRowHeight
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(range, id: \.self) { index in
                    SideBySideCellView(
                        cell: cell(at: index),
                        style: style,
                        digits: digits,
                        rowHeight: rowHeight
                    )
                }
            }
        }
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(range, id: \.self) { index in
                    Rectangle()
                        .fill(tint(at: index))
                        .frame(height: rowHeight)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            hoverAffordance(rowHeight: rowHeight)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                guard location.y >= 0 else {
                    hoveredRow = nil
                    return
                }
                let index = range.lowerBound + Int(location.y / rowHeight)
                hoveredRow = range.contains(index) ? index : nil
            case .ended:
                hoveredRow = nil
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Hover tracks the whole pane row (parity with unified), not the cell:
    // inside the scroller a cell is only as wide as its text.
    @ViewBuilder
    private func hoverAffordance(rowHeight: CGFloat) -> some View {
        if let index = hoveredRow,
            let anchor = anchor(at: index),
            let cell = cell(at: index),
            let model = commenting?.model,
            model.canComment
        {
            HStack {
                Spacer()
                DiffAddCommentButton(
                    anchor: anchor, line: cell.line, model: model,
                    iconSize: 13, frameSize: CGSize(width: 22, height: 20)
                )
                .padding(.trailing, style.horizontalPadding)
            }
            .frame(height: rowHeight)
            .background(
                DiffRowAccent.hover
                    .allowsHitTesting(false)
            )
            .offset(y: CGFloat(index - range.lowerBound) * rowHeight)
        }
    }

    private func cell(at index: Int) -> SideBySideCell? {
        side == .old ? rows[index].old : rows[index].new
    }

    private func anchor(at index: Int) -> DiffLineAnchor? {
        guard let commenting else { return nil }
        let anchors = DiffLineAnchor.anchors(for: rows[index], file: commenting.file)
        return side == .old ? anchors.old : anchors.new
    }

    private func tint(at index: Int) -> Color {
        // nil = filler cell opposite an unpaired line — washed, not clear.
        cell(at: index)?.line.kind.diffRowTint ?? Color.primary.opacity(0.04)
    }
}

nonisolated enum SideBySideAnchorSide {
    case old
    case new
}

extension DiffLineAnchor {
    // Context lines anchor on the new side (same convention as unified),
    // so hovering a context row in either pane targets one shared anchor.
    static func anchors(
        for row: SideBySideRow,
        file: String
    ) -> (old: DiffLineAnchor?, new: DiffLineAnchor?) {
        var new: DiffLineAnchor?
        if let cell = row.new {
            new = DiffLineAnchor(file: file, side: .new, line: cell.number)
        }
        var old: DiffLineAnchor?
        if let cell = row.old {
            switch cell.line.kind {
            case .removed:
                old = DiffLineAnchor(file: file, side: .old, line: cell.number)
            case .context, .added:
                old = new
            }
        }
        return (old, new)
    }
}

private struct SideBySideCellView: View {
    let cell: SideBySideCell?
    let style: DiffLineStyle
    let digits: Int
    let rowHeight: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if style.showsLineNumbers {
                Text(numberText)
                    .font(style.font)
                    .foregroundStyle(.tertiary)
            }
            Text(cell?.line.kind.diffSymbol ?? " ")
                .font(style.font)
                .foregroundStyle(cell?.line.kind.diffSymbolColor ?? .secondary)
                .frame(width: 14, alignment: .leading)
            if let cell {
                DiffLineText.styledText(for: cell.line)
                    .font(style.font)
                    .lineLimit(1)
                // Fixed-height panes can't take a marker row without
                // desyncing the two sides — render it inline instead.
                if cell.line.hasNoTrailingNewline {
                    Text(#"\ No newline at end of file"#)
                        .font(style.font)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .frame(height: rowHeight)
    }

    private var numberText: String {
        let value = cell.map { String($0.number) } ?? ""
        return String(repeating: " ", count: max(digits - value.count, 0)) + value
    }
}
