import SwiftUI

// Editor-wide focused values consumed by Commands (⌘S, ⌘W) and IssueCardSwitch
// (dirty-state lock). The historical "specEditor" prefix predates the rename to
// IssueDetail/DocEditor; the keys are kept so the command wiring stays stable.
extension FocusedValues {
    @Entry var specEditorIsActive: Bool?
    @Entry var specEditorSave: EditorAction?
    @Entry var specEditorClose: EditorAction?
    @Entry var specEditorDirtyFolderName: String?
}
