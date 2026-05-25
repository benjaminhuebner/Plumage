import SwiftUI

extension FocusedValues {
    // Published by the active ProjectWindow so File-menu commands can call
    // navigator.beginPendingCreate(...) without prop-drilling. Each command
    // calls .run() with the section it wants to open. A nil value disables
    // the menu items (no project window focused).
    @Entry var beginInlineCreate: InlineCreateInvoker?
}

struct InlineCreateInvoker: Equatable, @unchecked Sendable {
    let id: UUID
    let run: (PendingCreate.Section) -> Void

    init(_ run: @escaping (PendingCreate.Section) -> Void) {
        self.id = UUID()
        self.run = run
    }

    static func == (lhs: InlineCreateInvoker, rhs: InlineCreateInvoker) -> Bool {
        lhs.id == rhs.id
    }
}

struct NewSidebarItemCommands: Commands {
    @FocusedValue(\.beginInlineCreate) private var beginInlineCreate
    @FocusedValue(\.specEditorSave) private var editorSave

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Doc") {
                editorSave?.run()
                beginInlineCreate?.run(.managedFile(type: .docs))
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)

            Button("New Hook") {
                editorSave?.run()
                beginInlineCreate?.run(.managedFile(type: .hooks))
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)

            Button("New Skill") {
                editorSave?.run()
                beginInlineCreate?.run(.skill)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)

            Button("New Agent") {
                editorSave?.run()
                beginInlineCreate?.run(.managedFile(type: .agents))
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)

            Button("New Rule") {
                editorSave?.run()
                beginInlineCreate?.run(.managedFile(type: .rules))
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)

            // `O` would conflict with File → Open, so we use `Y` per the spec.
            Button("New Output Style") {
                editorSave?.run()
                beginInlineCreate?.run(.managedFile(type: .outputStyles))
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            .disabled(beginInlineCreate == nil)
        }
    }
}
