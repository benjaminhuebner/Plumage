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
        // Sendable KVO closure.
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
