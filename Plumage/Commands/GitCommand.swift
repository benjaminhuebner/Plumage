import SwiftUI

extension FocusedValues {
    @Entry var gitCommitAction: EditorAction?
    @Entry var gitPushAction: EditorAction?
    @Entry var gitPullAction: EditorAction?
}

struct GitCommand: Commands {
    @FocusedValue(\.gitCommitAction) private var commitAction
    @FocusedValue(\.gitPushAction) private var pushAction
    @FocusedValue(\.gitPullAction) private var pullAction

    var body: some Commands {
        CommandMenu("Git") {
            Button("Commit…") { commitAction?.run() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(commitAction == nil)
            Button("Push") { pushAction?.run() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(pushAction == nil)
            Button("Pull") { pullAction?.run() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(pullAction == nil)
        }
    }
}
