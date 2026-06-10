import SwiftUI

struct SpecEditorCommands: Commands {
    @FocusedValue(\.specEditorIsActive) private var isActive
    @FocusedValue(\.specEditorSave) private var save
    @FocusedValue(\.specEditorClose) private var close

    // `after: .saveItem`, not replacing: replacing wiped the standard Close
    // (⌘W) from the File menu app-wide. ⌘W is plain window-close everywhere
    // now (decided #00087, supersedes the #00008 ⌘W-as-Close-Spec choice);
    // the editor close hook gets its own ⌃⌘W. After the NavigationSplitView
    // refactor (issue #00024), `\.specEditorClose` no longer pops a stack —
    // it acts as a save-confirm hook for the focused editor (IssueDetailView
    // in the create-issue sheet still dismisses; DocEditorView commits the
    // buffer).
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
