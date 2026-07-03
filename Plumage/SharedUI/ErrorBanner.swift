import SwiftUI

// Shared inline error banner. Without a title it renders the full-width red
// strip (New Project / Migrate); with a title it renders the rounded card used
// by project settings, with optional retry and dismiss controls.
struct ErrorBanner: View {
    let message: String
    var title: String?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        if let title {
            card(title: title)
        } else {
            strip
        }
    }

    private var strip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.red)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Error: \(message)")
    }

    private func card(title: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onRetry {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
