import SwiftUI

extension EnvironmentValues {
    // Called by IssueCardSwitch when a tap (not a drag) ends on the card.
    // ProjectWindow wires this to the sidebar selection. Routing the tap
    // through here lets the card own its full gesture coordination via
    // ExclusiveGesture(Drag, Tap), so a drag-then-release-near-start no
    // longer opens the editor like NavigationLink's bridged button would.
    @Entry var openSpec: (NavigatorRoute) -> Void = { _ in }
    // KanbanColumnView's "+" button triggers a new issue. ProjectWindow
    // wires this to the create-issue sheet.
    @Entry var openCreateIssue: (IssueStatus) -> Void = { _ in }
    @Entry var dismissToOrigin: (() -> Void)?
}
