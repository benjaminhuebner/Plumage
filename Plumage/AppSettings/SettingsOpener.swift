import AppKit

enum SettingsOpener {
    // AppKit is the only reliable programmatic open for the SwiftUI Settings
    // scene — SettingsLink is a view with no action hook. The selector was
    // renamed in macOS 13, so fall back to the older name.
    static func open() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
