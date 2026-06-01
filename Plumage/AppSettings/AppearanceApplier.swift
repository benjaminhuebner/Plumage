import AppKit

@MainActor
enum AppearanceApplier {
    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = appearance.nsAppearance
    }

    static func applyStored(from defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: AppAppearance.storageKey)
        apply(AppAppearance.resolve(from: stored))
    }
}
