import SwiftUI

extension FocusedValues {
    // Presence marker published by the Welcome scene so the menu's "New
    // Project…" ⌘N is scoped to it. Optional → the command disables when Welcome
    // isn't the focused scene (in a Project window ⌘N is "New Issue"; scene focus
    // keeps exactly one of the two enabled).
    @Entry var newProjectAvailable: Bool?
}

struct NewProjectCommand: Commands {
    @FocusedValue(\.newProjectAvailable) private var available
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project…") {
                openWindow(id: "new-project")
                dismissWindow(id: "welcome")
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(available == nil)
        }
    }
}
