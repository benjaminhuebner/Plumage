import AppKit
import Foundation

nonisolated struct ProductionAppLauncher: AppLaunching {
    func openApp(at url: URL) async throws -> Int32? {
        // NSWorkspace.openApplication returns the NSRunningApplication so we
        // can both force a new instance (createsNewApplicationInstance) AND
        // track its termination via the .didTerminateApplicationNotification.
        // /usr/bin/open -n forced a new instance too but gave back no handle.
        try await openOnMain(at: url)
    }

    @MainActor
    private func openOnMain(at url: URL) async throws -> Int32 {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return app.processIdentifier
    }
}
