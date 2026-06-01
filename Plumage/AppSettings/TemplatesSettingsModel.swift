import Foundation

// Feature-local model for the Templates settings tab. Owns the catalog of bundled
// scaffold assets, the override read/write, the enable/disable toggles, the agents
// store and the live CLAUDE.md preview. State-as-bridge: any disk I/O is funnelled
// through this @MainActor type so the view stays declarative.
@MainActor
@Observable
final class TemplatesSettingsModel {
    private let overrides: ScaffoldOverrides

    init(overrides: ScaffoldOverrides = .standard()) {
        self.overrides = overrides
    }
}
