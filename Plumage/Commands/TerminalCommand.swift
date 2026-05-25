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
                tabs?.addTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(tabs == nil)

            // ⌘W is also bound on IssueDetail's dismiss; SwiftUI routes to
            // whichever view holds keyboard focus, so this button stays
            // disabled (and the chord falls through) whenever there is no
            // closable terminal tab — including when the inspector is shut.
            Button("Close Terminal Tab") {
                guard let tabs, let id = tabs.selectedTabID else { return }
                tabs.closeTab(id: id)
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!(tabs?.canCloseActiveTab ?? false))

            ForEach(1...9, id: \.self) { number in
                Button("Switch to Terminal Tab \(number)") {
                    tabs?.selectTab(at: number - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(number)")),
                    modifiers: [.command]
                )
                .disabled((tabs?.tabs.count ?? 0) < number)
            }
        }
    }
}
