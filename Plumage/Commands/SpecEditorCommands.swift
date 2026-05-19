import SwiftUI

struct SpecEditorCommands: Commands {
    @FocusedValue(\.specEditorIsActive) private var isActive
    @FocusedValue(\.specEditorSave) private var save
    @FocusedValue(\.specEditorClose) private var close

    // Both commands sit in `.saveItem` (replacing). When the editor is active,
    // the File-menu Cmd-W wins over the Window-menu default Close — when the
    // editor is inactive, both buttons are disabled and the system default
    // Cmd-W (window close) takes over. After the NavigationSplitView refactor
    // (issue #00024), `\.specEditorClose` no longer pops a stack — it acts as
    // a save-confirm hook for the focused editor (IssueDetailView in the
    // create-issue sheet still dismisses; DocEditorView commits the buffer).
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save Spec") {
                save?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isActive == nil || save == nil)

            Button("Close Spec") {
                close?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(isActive == nil || close == nil)
        }
    }
}
