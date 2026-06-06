import SwiftUI

extension FocusedValues {
    // Set by the active ProjectWindow scene. When fired, it pushes
    // IssueDetailView in creating mode with the default-column status.
    @Entry var createIssueInDefaultColumn: EditorAction?
}

struct NewIssueCommand: Commands {
    @FocusedValue(\.createIssueInDefaultColumn) private var createIssue
    @FocusedValue(\.specEditorSave) private var editorSave

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("New Issue") {
                editorSave?.run()
                createIssue?.run()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(createIssue == nil)
        }
    }
}
