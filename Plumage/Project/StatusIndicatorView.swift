import SwiftUI

struct StatusIndicatorView: View {
    let state: StatusIndicatorModel.IndicatorState

    var body: some View {
        HStack(spacing: 6) {
            dot
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .capsule)
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(tooltip))
    }

    @ViewBuilder
    private var dot: some View {
        switch state {
        case .loading:
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
                .opacity(0.4)
                .modifier(PulseModifier())
        case .ok:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .unsupported:
            Circle().fill(.yellow).frame(width: 8, height: 8)
        case .missing, .failed:
            Circle().fill(.red).frame(width: 8, height: 8)
        }
    }

    private var label: String {
        switch state {
        case .loading: return "checking…"
        case .ok(let check): return "claude \(check.version) ready"
        case .unsupported(let check): return "claude \(check.version) unsupported"
        case .missing: return "claude not found"
        case .failed: return "claude failed"
        }
    }

    private var tooltip: String {
        switch state {
        case .loading:
            return "Detecting `claude` binary…"
        case .ok(let check):
            return """
                Found at \(check.binaryURL.path).
                Version \(check.version) (supported: \(SupportedClaudeVersion.supportedRangeDescription)).
                """
        case .unsupported(let check):
            return """
                Version \(check.version) is outside supported range \
                \(SupportedClaudeVersion.supportedRangeDescription). \
                Some features may not work — update via \
                `\(SupportedClaudeVersion.installCommand)`.
                """
        case .missing:
            return """
                Searched \(SupportedClaudeVersion.searchPathDescription). \
                Install via `\(SupportedClaudeVersion.installCommand)`.
                """
        case .failed(let error):
            return error.humanReadableMessage
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .loading: return "Claude status: checking"
        case .ok: return "Claude status: ready"
        case .unsupported: return "Claude status: unsupported"
        case .missing: return "Claude status: not found"
        case .failed: return "Claude status: failed"
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 1.0 : 0.4)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

#Preview("Loading") {
    StatusIndicatorView(state: .loading)
        .padding()
}

#Preview("OK") {
    StatusIndicatorView(
        state: .ok(
            VersionCheck(
                version: SemanticVersion(major: 1, minor: 2, patch: 3),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: true
            )
        )
    )
    .padding()
}

#Preview("Unsupported") {
    StatusIndicatorView(
        state: .unsupported(
            VersionCheck(
                version: SemanticVersion(major: 0, minor: 9, patch: 0),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: false
            )
        )
    )
    .padding()
}

#Preview("Missing") {
    StatusIndicatorView(state: .missing)
        .padding()
}

#Preview("Failed") {
    StatusIndicatorView(
        state: .failed(.nonZeroExit(code: 127, stderr: "command not found"))
    )
    .padding()
}
