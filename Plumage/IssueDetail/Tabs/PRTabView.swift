import SwiftUI

struct PRTabView: View {
    let blocks: [PRMarkdownParser.Block]

    // Scroll-less on purpose: the PR tab wraps this in its own ScrollView.
    var body: some View {
        if blocks.isEmpty {
            BodyTabEmptyState(
                symbol: "doc.text.magnifyingglass",
                title: "No pr.md yet",
                detail:
                    "Created by `/plumage-implement` once the issue moves to `waiting-for-review`."
            )
            .frame(minHeight: 240)
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: PRMarkdownParser.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .padding(.top, level == 1 ? 4 : 6)
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}
