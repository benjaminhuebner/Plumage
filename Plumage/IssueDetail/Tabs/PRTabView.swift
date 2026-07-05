import SwiftUI

struct PRTabView: View {
    let blocks: [MarkdownBlockParser.Block]

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
            MarkdownBlocksView(blocks: blocks)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }
}
