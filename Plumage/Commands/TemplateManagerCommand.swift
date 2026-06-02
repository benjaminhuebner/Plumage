import SwiftUI

// Window-menu entry for the app-global Template Manager. Ungated (unlike the
// focus-scoped New Project / New Issue commands) — it works with zero project
// windows open, like Settings. Mirrors NewProjectCommand's structure.
struct TemplateManagerCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Template Manager") {
                openWindow(id: "template-manager")
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
