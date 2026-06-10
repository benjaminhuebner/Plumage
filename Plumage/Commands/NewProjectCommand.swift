import SwiftUI

extension FocusedValues {
    // New Issue carries ⌘N unconditionally, so New Project must bind ⌘N only
    // when Welcome is key. Welcome publishes this marker; the button gates on it.
    @Entry var newProjectAvailable: Bool?
}

struct NewProjectMenuButton: View {
    @FocusedValue(\.newProjectAvailable) private var welcomeFocused
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if welcomeFocused != nil {
            button.keyboardShortcut("n", modifiers: .command)
        } else {
            button
        }
    }

    private var button: some View {
        Button("New Project…") {
            openWindow(id: "new-project")
            dismissWindow(id: "welcome")
        }
    }
}

struct MigrateProjectMenuButton: View {
    // Injected, not @Environment: CommandGroup views don't inherit the scene environment.
    let migrationRequest: MigrationRequest

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Migrate Project…") {
            MigrateProjectCommand.presentPicker(
                request: migrationRequest,
                openWindow: openWindow,
                dismissWindow: dismissWindow
            )
        }
    }
}

// One replacing-group for all three: a split replacing/after anchor can't order
// Open between New and Migrate — it lands before New or after Migrate.
struct ProjectFileCommands: Commands {
    let recentProjects: RecentProjects
    let migrationRequest: MigrationRequest

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            NewProjectMenuButton()
            OpenProjectMenuButton(recentProjects: recentProjects)
            OpenRecentMenu(recentProjects: recentProjects)
            MigrateProjectMenuButton(migrationRequest: migrationRequest)
        }
    }
}
