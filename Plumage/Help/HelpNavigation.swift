import Observation

// Lets the Help menu preselect a topic before opening the help window.
@MainActor
@Observable
final class HelpNavigation {
    var selectedTopicID: HelpTopic.ID? = HelpTopic.all.first?.id
}
