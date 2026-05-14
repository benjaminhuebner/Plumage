import SwiftUI

extension FocusedValues {
    // Set by the active ProjectWindow scene. When fired, it pushes
    // IssueDetailView in creating mode with the default-column status.
    @Entry var createIssueInDefaultColumn: (() -> Void)?
}

struct NewIssueCommand: Commands {
    @FocusedValue(\.createIssueInDefaultColumn) private var createIssue
    @FocusedValue(\.specEditorSave) private var editorSave

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Issue") {
                editorSave?()
                createIssue?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(createIssue == nil)
        }
    }
}
