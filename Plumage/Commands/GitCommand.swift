import SwiftUI

extension FocusedValues {
    @Entry var gitInitAction: EditorAction?
    @Entry var gitCommitAction: EditorAction?
    @Entry var gitCreateTagAction: EditorAction?
    @Entry var gitPushAction: EditorAction?
    @Entry var gitPullAction: EditorAction?
    @Entry var gitAddRemoteAction: EditorAction?
    @Entry var gitImportIssuesAction: EditorAction?
}

struct GitCommand: Commands {
    @FocusedValue(\.gitInitAction) private var initAction
    @FocusedValue(\.gitCommitAction) private var commitAction
    @FocusedValue(\.gitCreateTagAction) private var createTagAction
    @FocusedValue(\.gitPushAction) private var pushAction
    @FocusedValue(\.gitPullAction) private var pullAction
    @FocusedValue(\.gitAddRemoteAction) private var addRemoteAction
    @FocusedValue(\.gitImportIssuesAction) private var importIssuesAction

    var body: some Commands {
        CommandMenu("Git") {
            // A non-repo folder offers only initialization; a repo has no init
            // action and shows the repo group instead.
            if initAction != nil {
                Button("Initialize Git Repository…") { initAction?.run() }
            } else {
                repoItems
            }
        }
    }

    @ViewBuilder
    private var repoItems: some View {
        // ⌥⌘K, not ⌘K: ⌘K is clear-terminal muscle memory and a menu
        // chord would steal it from the embedded terminal (⌥⌘C is
        // NSTextView's copyStyle:, see TerminalCommand).
        Button("Commit…") { commitAction?.run() }
            .keyboardShortcut("k", modifiers: [.command, .option])
            .disabled(commitAction == nil)
        Button("Tag…") { createTagAction?.run() }
            .disabled(createTagAction == nil)
        Divider()
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
