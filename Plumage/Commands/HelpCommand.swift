import SwiftUI

// Without a help book, the system "Plumage Help" item dead-ends in an error
// alert — replacing .help routes it to the in-app help window instead.
struct HelpCommands: Commands {
    let helpNavigation: HelpNavigation

    var body: some Commands {
        CommandGroup(replacing: .help) {
            HelpMenuContent(helpNavigation: helpNavigation)
        }
    }
}

private struct HelpMenuContent: View {
    // Injected, not @Environment: CommandGroup views don't inherit the scene environment.
    let helpNavigation: HelpNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Plumage Help") {
            openWindow(id: "help")
        }
        // The system Help search skips the Help menu's own items — these are
        // for scanning and clicking; content search lives in the help window.
        ForEach(HelpTopic.sections) { section in
            Divider()
            ForEach(section.topics) { topic in
                Button(topic.title) {
                    helpNavigation.selectedTopicID = topic.id
                    openWindow(id: "help")
                }
            }
        }
    }
}
