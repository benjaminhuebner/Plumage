import SwiftUI

extension FocusedValues {
    // Published by the Welcome scene so the menu's "New Project…" command can
    // open the wizard sheet. Optional → the command disables when Welcome isn't
    // the focused scene (in a Project window ⌘N is "New Issue"; scene focus keeps
    // exactly one of the two enabled).
    @Entry var newProjectPresented: Binding<Bool>?
}

struct NewProjectCommand: Commands {
    @FocusedValue(\.newProjectPresented) private var presented

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project…") {
                presented?.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(presented == nil)
        }
    }
}
