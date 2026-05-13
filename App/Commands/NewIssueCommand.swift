import SwiftUI

extension FocusedValues {
    @Entry var newIssueSheetIsPresented: Binding<Bool>?
}

struct NewIssueCommand: Commands {
    @FocusedValue(\.newIssueSheetIsPresented) private var sheetBinding

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Issue") {
                sheetBinding?.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(sheetBinding == nil)
        }
    }
}
