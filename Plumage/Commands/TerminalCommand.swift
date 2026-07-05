import SwiftUI

struct TerminalCommand: Commands {
    @FocusedBinding(\.terminalToggle) private var inspector
    @FocusedBinding(\.chatDockToggle) private var chatDock
    @FocusedValue(\.terminalTabs) private var tabs
    @AppStorage(TerminalFontPreference.defaultsKey)
    private var terminalFontSize: Double = TerminalFontPreference.defaultSize

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            // ⌃⌥⌘T: plain ⌥⌘T is the system Show/Hide Toolbar chord and
            // would shadow it in every window with a toolbar.
            Button("Toggle Terminal Inspector") {
                inspector?.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .control])
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

        // Tab management is content manipulation, not view chrome — its own
        // menu instead of the View menu.
        CommandMenu("Terminal") {
            Button("New Terminal Tab") {
                // Open the inspector so the new tab is actually visible
                // (and its SwiftTermBridge mounts so the PTY can spawn).
                inspector = true
                tabs?.addTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(tabs == nil)

            // ⇧⌘W: plain ⌘W is window-close and ⌥⌘W would shadow the
            // system "Close All" alternate in the File menu.
            Button("Close Terminal Tab") {
                tabs?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(!(tabs?.canCloseActiveTab ?? false))

            Divider()

            // ⌥⌘digit: plain ⌘1-9 is conventionally window/navigator
            // switching (Finder, Safari, Xcode) — don't take it app-wide.
            ForEach(1...9, id: \.self) { number in
                Button(menuTitle(for: number)) {
                    // Opening the inspector makes the switch visible —
                    // selecting a hidden tab read as a silent no-op.
                    inspector = true
                    tabs?.selectTab(number - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(number)")),
                    modifiers: [.command, .option]
                )
                .disabled((tabs?.count ?? 0) < number)
            }

            Divider()

            // Global preference, not per-tab: every mounted terminal observes
            // the @AppStorage value and reflows via updateNSView.
            Button("Increase Text Size") {
                terminalFontSize = TerminalFontPreference.increased(from: terminalFontSize)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Decrease Text Size") {
                terminalFontSize = TerminalFontPreference.decreased(from: terminalFontSize)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button("Default Text Size") {
                terminalFontSize = TerminalFontPreference.defaultSize
            }
            .keyboardShortcut("0", modifiers: [.command])
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
