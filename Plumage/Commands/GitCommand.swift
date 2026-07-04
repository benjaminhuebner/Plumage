import SwiftUI

extension FocusedValues {
    @Entry var gitCommitAction: EditorAction?
    @Entry var gitPushAction: EditorAction?
    @Entry var gitPullAction: EditorAction?
    @Entry var gitAddRemoteAction: EditorAction?
    @Entry var gitImportIssuesAction: EditorAction?
}

struct GitCommand: Commands {
    @FocusedValue(\.gitCommitAction) private var commitAction
    @FocusedValue(\.gitPushAction) private var pushAction
    @FocusedValue(\.gitPullAction) private var pullAction
    @FocusedValue(\.gitAddRemoteAction) private var addRemoteAction
    @FocusedValue(\.gitImportIssuesAction) private var importIssuesAction

    var body: some Commands {
        CommandMenu("Git") {
            // ⌥⌘K, not ⌘K: ⌘K is clear-terminal muscle memory and a menu
            // chord would steal it from the embedded terminal (⌥⌘C is
            // NSTextView's copyStyle:, see TerminalCommand).
            Button("Commit…") { commitAction?.run() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(commitAction == nil)
            Button("Push") { pushAction?.run() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(pushAction == nil)
            Button("Pull") { pullAction?.run() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(pullAction == nil)
            Divider()
            Button("Add Remote…") { addRemoteAction?.run() }
                .disabled(addRemoteAction == nil)
            Divider()
            Button("Import GitHub Issues…") { importIssuesAction?.run() }
                .disabled(importIssuesAction == nil)
        }
    }
}
