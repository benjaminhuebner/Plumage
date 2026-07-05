import Foundation

// nonisolated so topics can cross to an off-main markdown parse.
nonisolated struct HelpTopic: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let markdown: String

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || markdown.localizedCaseInsensitiveContains(query)
    }
}

nonisolated struct HelpSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let topics: [HelpTopic]
}

extension HelpTopic {
    static let all: [HelpTopic] = sections.flatMap(\.topics)
}
