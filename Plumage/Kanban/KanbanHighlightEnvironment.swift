import SwiftUI

extension EnvironmentValues {
    @Entry var kanbanHighlightedID: String?
    // Called by IssueCardSwitch when a tap (not a drag) ends on the card.
    // ProjectWindow wires this to NavigationPath.append. Routing the tap
    // through here lets the card own its full gesture coordination via
    // ExclusiveGesture(Drag, Tap), so a drag-then-release-near-start no
    // longer opens the editor like NavigationLink's bridged button would.
    @Entry var openSpec: (String) -> Void = { _ in }
}
