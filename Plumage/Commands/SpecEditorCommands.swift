import SwiftUI

struct SpecEditorCommands: Commands {
    @FocusedValue(\.specEditorIsActive) private var isActive
    @FocusedValue(\.specEditorSave) private var save
    @FocusedValue(\.specEditorClose) private var close

    // `after: .saveItem`, not replacing: replacing wiped the standard Close (⌘W)
    // from the File menu app-wide. ⌘W stays plain window-close; the editor close
    // hook (a save-confirm hook, not a stack pop) lives on ⌃⌘W.
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
