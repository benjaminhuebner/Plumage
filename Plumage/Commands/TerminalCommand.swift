import SwiftUI

struct TerminalCommand: Commands {
    @FocusedBinding(\.terminalToggle) private var inspector
    @FocusedBinding(\.chatDockToggle) private var chatDock
    @FocusedValue(\.terminalTabs) private var tabs

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

            Button("New Terminal Tab") {
                // Open the inspector so the new tab is actually visible
                // (and its SwiftTermBridge mounts so the PTY can spawn).
                inspector = true
                tabs?.addTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(tabs == nil)

            // ⌥⌘W instead of ⌘W: plain ⌘W also bound by SpecEditorCommands
            // (Close Spec) and AppKit's default Close Window. SwiftUI does
            // NOT route by focus when two Commands share a chord — it picks
            // whichever happens to be enabled by .disabled(). With ⌥⌘W
            // there's no collision; the user gets an explicit terminal-tab
            // close that doesn't fight the editor or the window.
            Button("Close Terminal Tab") {
                tabs?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(!(tabs?.canCloseActiveTab ?? false))

            ForEach(1...9, id: \.self) { number in
                Button(menuTitle(for: number)) {
                    tabs?.selectTab(number - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(number)")),
                    modifiers: [.command]
                )
                .disabled((tabs?.count ?? 0) < number)
            }
        }
    }

    private func menuTitle(for number: Int) -> String {
        if number == 1 {
            let firstTitle = tabs?.firstTabTitle ?? "Main Terminal"
            return "Switch to \(firstTitle)"
        }
        return "Switch to Terminal Tab \(number)"
    }
}
