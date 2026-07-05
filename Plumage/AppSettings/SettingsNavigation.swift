import Observation

nonisolated enum SettingsTab: Hashable, Sendable {
    case general
    case issueTypes
    case templates
    case usage
    case accounts
}

// Lets another window (e.g. the sync sheet's "Add GitHub account…" action)
// preselect a Settings pane before opening the Settings window.
@MainActor
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab = .general
}
