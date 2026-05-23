import SwiftUI

struct TerminalCommand: Commands {
    @FocusedBinding(\.terminalToggle) private var inspector
    @FocusedBinding(\.chatDockToggle) private var chatDock

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Terminal Inspector") {
                inspector?.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(inspector == nil)

            // ⌥⌘J chosen over ⌥⌘C: AppKit's NSTextView reserves ⌥⌘C for
            // "Copy Style" (copyStyle:). Binding the chat-dock toggle to
            // ⌥⌘C silently fights text inputs (ChatInputField,
            // DocEditorView) — the chord either no-ops or copies attributes
            // instead of toggling the dock. ⌥⌘J has no known AppKit/Xcode
            // collision.
            Button("Toggle Chat") {
                chatDock?.toggle()
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .disabled(chatDock == nil)
        }
    }
}
