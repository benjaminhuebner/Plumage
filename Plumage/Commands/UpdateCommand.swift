import SwiftUI

// The updater is passed in explicitly rather than read from `@Environment`:
// `.commands { }` content does not inherit the scene environment, so an
// `@Environment` lookup inside a command button crashes on first use
// (notes.md 2026-05-12 #00002).
struct UpdateCommands: Commands {
    let updater: UpdaterModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updater: updater)
        }
    }
}
