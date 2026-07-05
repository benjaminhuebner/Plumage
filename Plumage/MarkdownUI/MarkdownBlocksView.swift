import SwiftUI

// Scroll-less on purpose: callers wrap it in their own ScrollView and own
// the surrounding padding.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlockParser.Block]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https"
                else { return .discarded }
                return .systemAction
            })
    }

    @ViewBuilder
    private func view(for block: MarkdownBlockParser.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .padding(.top, level == 1 ? 4 : 6)
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let indent, let text):
            listRow(indent: indent, text: text) {
                Text("•").foregroundStyle(.secondary)
            }
        case .orderedItem(let indent, let number, let text):
            listRow(indent: indent, text: text) {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .taskItem(let indent, let done, let text):
            listRow(indent: indent, text: text) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .imageScale(.small)
            }
        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        case .codeBlock(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .blank:
            Color.clear.frame(height: 4)
        }
    }

    private func listRow(
        indent: Int,
        text: AttributedString,
        @ViewBuilder marker: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker()
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(min(indent, 6)) * 16)
    }

    private func tableView(headers: [AttributedString], rows: [[AttributedString]]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                    Text(cell).bold()
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}
