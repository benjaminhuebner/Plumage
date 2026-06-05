import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class UpdaterModel {
    private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init(startingUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Sparkle's `canCheckForUpdates` is KVO-compliant but fires on whatever
        // thread the updater happens to be on; hop to the main actor when
        // assigning so SwiftUI's @Observable tracking sees the change on main.
        // Read the Sendable `change.newValue` rather than the (MainActor-isolated)
        // `updater.canCheckForUpdates` property, which can't be touched from this
        // @Sendable KVO closure. The closure only crosses back to the main actor
        // via this Task; it captures nothing of `self` except the weak reference,
        // so `UpdaterModel`'s implicit @MainActor Sendable conformance carries it.
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.new]
        ) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
        // Seed the initial value explicitly instead of via the KVO `.initial`
        // option: that fires synchronously mid-init, and a direct read here is
        // safe (this init runs on the main actor) and keeps the init path
        // deterministic rather than relying on the Task hop deferring past init.
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
