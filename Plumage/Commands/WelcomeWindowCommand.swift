import SwiftUI

struct WelcomeWindowCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            WelcomeWindowMenuButton()
        }
    }
}

private struct WelcomeWindowMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Welcome to Plumage") {
            openWindow(id: "welcome")
        }
        .keyboardShortcut(KeyEquivalent("0"), modifiers: [.command, .shift])
    }
}
