#if DEBUG
import SwiftUI

struct TerminalSpikeCommand: Commands {
    @FocusedBinding(\.terminalSpikeToggle) private var shown

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Terminal Spike") {
                shown?.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(shown == nil)

            Button("Toggle Terminal Spike (Xcode-style)") {
                shown?.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(shown == nil)
        }
    }
}
#endif
