import SwiftUI

// Triangle (not a circle) so the warning reads by shape alone — the cue must
// survive color-blindness / Differentiate Without Color where red is the only
// other signal. No imageScale so it tracks the row's Dynamic Type size.
// accessibilityHidden because the owning row folds the message into its own
// VoiceOver label; without this the icon is a second, duplicate focus stop.
struct EmptyContextWarningIcon: View {
    let message: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .help(message)
            .accessibilityHidden(true)
    }

    static func fileMessage(_ name: String) -> String {
        "\(name) is empty — Claude has no project context"
    }

    static let folderMessage = "Contains an empty context file — Claude has no project context"
}
