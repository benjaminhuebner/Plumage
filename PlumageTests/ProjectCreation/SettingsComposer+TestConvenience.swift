import Foundation

@testable import Plumage

// Test-only shorthand: production callers resolve a template id before composing.
extension SettingsComposer {
    nonisolated func settingsJSON(
        for kind: ProjectKind, toggles: ScaffoldToggles = ScaffoldToggles(),
        userWirings: [HookWiring] = []
    ) throws -> Data {
        try settingsJSON(forTemplate: kind.rawValue, toggles: toggles, userWirings: userWirings)
    }
}
