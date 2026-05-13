import SwiftUI

struct SpecEditorCommands: Commands {
    @FocusedValue(\.specEditorIsActive) private var isActive
    @FocusedValue(\.specEditorSave) private var save
    @FocusedValue(\.specEditorClose) private var close

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save Spec") {
                save?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isActive == nil || save == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Close Spec") {
                close?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(isActive == nil || close == nil)
        }
    }
}
