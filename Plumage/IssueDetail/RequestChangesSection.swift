import SwiftUI

struct RequestChangesSection: View {
    let openCount: Int
    let isBusy: Bool
    let errorMessage: String?
    let onRequestChanges: () -> Void
    let onDismissError: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Request changes")
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Dismiss", action: onDismissError)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Request Changes", action: onRequestChanges)
                    .buttonStyle(.borderedProminent)
                    .disabled(openCount == 0 || isBusy)
            }
        }
    }

    private var subtitle: String {
        switch openCount {
        case 0:
            return "Add review comments in the Diff tab to request changes."
        case 1:
            return "Sends 1 open review comment back to the agent as a spec task."
        default:
            return "Sends \(openCount) open review comments back to the agent as spec tasks."
        }
    }
}

#Preview("Open findings") {
    RequestChangesSection(
        openCount: 3, isBusy: false, errorMessage: nil,
        onRequestChanges: {}, onDismissError: {}
    )
    .padding()
    .frame(width: 480)
}

#Preview("No findings") {
    RequestChangesSection(
        openCount: 0, isBusy: false, errorMessage: nil,
        onRequestChanges: {}, onDismissError: {}
    )
    .padding()
    .frame(width: 480)
}

#Preview("Error") {
    RequestChangesSection(
        openCount: 2, isBusy: false, errorMessage: "spec.md could not be written",
        onRequestChanges: {}, onDismissError: {}
    )
    .padding()
    .frame(width: 480)
}
