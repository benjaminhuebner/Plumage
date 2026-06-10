import SwiftUI

struct SpecEditorCommands: Commands {
    @FocusedValue(\.specEditorIsActive) private var isActive
    @FocusedValue(\.specEditorSave) private var save
    @FocusedValue(\.specEditorClose) private var close

    // `after: .saveItem`, not replacing: replacing wiped the standard Close
    // (⌘W) from the File menu app-wide. ⌘W stays plain window-close; the
    // editor close hook lives on ⌃⌘W. `\.specEditorClose` does not pop a
    // stack — it is a save-confirm hook for the focused editor.
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Save Spec") {
                save?.run()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isActive == nil || save == nil)

            Button("Close Spec") {
                close?.run()
            }
            .keyboardShortcut("w", modifiers: [.command, .control])
            .disabled(isActive == nil || close == nil)
        }
    }
}
