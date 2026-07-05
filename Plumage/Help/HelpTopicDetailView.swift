import SwiftUI

struct HelpTopicDetailView: View {
    let topic: HelpTopic
    @State private var blocks: [MarkdownBlockParser.Block] = []

    var body: some View {
        ScrollView {
            MarkdownBlocksView(blocks: blocks)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .task(id: topic.id) {
            let markdown = topic.markdown
            blocks = await Task.detached { MarkdownBlockParser.parse(markdown) }.value
        }
    }
}
