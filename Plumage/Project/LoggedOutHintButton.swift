import SwiftUI

struct LoggedOutHintButton: View {
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 11, weight: .medium))
                Text("Login required")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.borderless)
        .help("Claude CLI is not logged in.")
        .accessibilityIdentifier("logged-out-hint")
        .accessibilityLabel(Text("Claude CLI login required"))
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            LoggedOutPopover()
        }
    }
}

struct LoggedOutPopover: View {
    @State private var didCopy = false
    static let loginCommand = "claude login"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude CLI not logged in")
                .font(.headline)
            Text(
                "Plumage reads Claude usage from the same keychain item the CLI stores its OAuth token in. Once you sign in, the usage pill will populate automatically."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            commandRow
            Text("Then relaunch this window or wait for the next refresh tick.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .accessibilityIdentifier("logged-out-popover")
    }

    @ViewBuilder
    private var commandRow: some View {
        HStack(spacing: 8) {
            Text(Self.loginCommand)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quinary)
                )
                .textSelection(.enabled)
            Spacer()
            Button {
                copyCommand()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(didCopy ? "Copied" : "Copy to clipboard")
            .accessibilityIdentifier("logged-out-copy-button")
        }
    }

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.loginCommand, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}
