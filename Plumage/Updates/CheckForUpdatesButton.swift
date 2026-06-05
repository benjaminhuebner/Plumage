import SwiftUI

struct CheckForUpdatesButton: View {
    let updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
