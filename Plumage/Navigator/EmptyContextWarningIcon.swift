import SwiftUI

// Always-visible red marker for an effectively-empty foundation context file
// (CLAUDE.md / PROJECT.md). Shown on the file's tree row, its pinned shortcut,
// and the collapsed folder that currently hides it. Carries help + a matching
// VoiceOver label so the warning is never a silent visual-only cue.
struct EmptyContextWarningIcon: View {
    let message: String

    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
            .imageScale(.small)
            .help(message)
            .accessibilityLabel(message)
    }

    static func fileMessage(_ name: String) -> String {
        "\(name) is empty — Claude has no project context"
    }

    static let folderMessage = "Contains an empty context file — Claude has no project context"
}
