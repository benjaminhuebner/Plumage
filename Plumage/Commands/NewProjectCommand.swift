import SwiftUI

extension FocusedValues {
    // Welcome publishes this so ⌘N can be scoped to it: in a Project window the
    // marker is absent and ⌘N belongs to New Issue instead. The menu items stay
    // enabled everywhere regardless — only the shortcut is gated.
    @Entry var newProjectAvailable: Bool?
}

struct NewProjectCommand: Commands {
    let migrationRequest: MigrationRequest

    @FocusedValue(\.newProjectAvailable) private var welcomeFocused
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            newProjectButton
            Button("Migrate Project…") {
                MigrateProjectCommand.presentPicker(
                    request: migrationRequest,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            }
        }
    }

    @ViewBuilder
    private var newProjectButton: some View {
        if welcomeFocused != nil {
            newProjectLabel
                .keyboardShortcut("n", modifiers: .command)
        } else {
            newProjectLabel
        }
    }

    private var newProjectLabel: some View {
        Button("New Project…") {
            openWindow(id: "new-project")
            dismissWindow(id: "welcome")
        }
    }
}
