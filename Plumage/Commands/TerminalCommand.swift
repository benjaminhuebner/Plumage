import SwiftUI

struct TerminalCommand: Commands {
    @FocusedBinding(\.terminalToggle) private var shown

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Terminal") {
                shown?.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(shown == nil)

            Button("Toggle Terminal (Xcode-style)") {
                shown?.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(shown == nil)
        }
    }
}
