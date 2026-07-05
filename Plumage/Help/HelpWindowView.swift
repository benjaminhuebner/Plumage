import SwiftUI

struct HelpWindowView: View {
    @Environment(HelpNavigation.self) private var helpNavigation
    @State private var searchText = ""

    private var visibleSections: [HelpSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return HelpTopic.sections }
        return HelpTopic.sections.compactMap { section in
            let topics = section.topics.filter { $0.matches(query) }
            guard !topics.isEmpty else { return nil }
            return HelpSection(id: section.id, title: section.title, topics: topics)
        }
    }

    var body: some View {
        @Bindable var helpNavigation = helpNavigation
        NavigationSplitView {
            List(selection: $helpNavigation.selectedTopicID) {
                ForEach(visibleSections) { section in
                    Section(section.title) {
                        ForEach(section.topics) { topic in
                            Label(topic.title, systemImage: topic.systemImage)
                                .tag(topic.id)
                        }
                    }
                }
            }
            .overlay {
                if visibleSections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let topic = HelpTopic.all.first(where: { $0.id == helpNavigation.selectedTopicID }) {
                HelpTopicDetailView(topic: topic)
            } else {
                ContentUnavailableView("Select a Topic", systemImage: "questionmark.circle")
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .navigationTitle("Plumage Help")
        .frame(minWidth: 700, minHeight: 440)
    }
}
