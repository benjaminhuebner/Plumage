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

            Button("Toggle Terminal Inspector (Xcode-style)") {
                inspector?.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(inspector == nil)

            Button("Toggle Chat") {
                chatDock?.toggle()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(chatDock == nil)
        }
    }
}
