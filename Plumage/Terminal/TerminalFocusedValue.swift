import SwiftUI

extension FocusedValues {
    @Entry var terminalToggle: Binding<Bool>?
    @Entry var chatDockToggle: Binding<Bool>?
    // The tabs binding is a snapshot+actions value type, not the model
    // reference. Commands bodies don't observe @Observable mutations on a
    // class instance the way View bodies do — re-publishing the model never
    // re-evaluates `.disabled(tabs?.tabs.count …)`. Wrapping snapshot fields
    // in an Equatable struct forces re-publication whenever the publishing
    // view body re-renders, which IS triggered by @Observable mutations.
    @Entry var terminalTabs: TerminalTabsBinding?
}

struct TerminalTabsBinding: Equatable {
    let count: Int
    let canCloseActiveTab: Bool
    let firstTabTitle: String

    // Actions capture the model strongly. Excluded from Equatable so that
    // re-publication is driven by the snapshot fields above, not by closure
    // identity (which changes every body re-eval).
    let addTab: () -> Void
    let closeActiveTab: () -> Void
    let selectTab: (Int) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.count == rhs.count
            && lhs.canCloseActiveTab == rhs.canCloseActiveTab
            && lhs.firstTabTitle == rhs.firstTabTitle
    }
}
