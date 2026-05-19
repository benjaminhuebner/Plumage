import SwiftUI

struct ProjectStatusBar: View {
    let indicatorState: StatusIndicatorModel.IndicatorState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Spacer()
                statusDot
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .help(tooltip)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityValue(Text(tooltip))
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch indicatorState {
        case .loading:
            Circle()
                .fill(.gray)
                .frame(width: 6, height: 6)
                .opacity(0.4)
                .modifier(PulseModifier())
        case .ok:
            Circle().fill(.green).frame(width: 6, height: 6)
        case .unsupported:
            Circle().fill(.yellow).frame(width: 6, height: 6)
        case .missing, .failed:
            Circle().fill(.red).frame(width: 6, height: 6)
        }
    }

    private var label: String {
        switch indicatorState {
        case .loading: return "checking…"
        case .ok(let check): return "claude \(check.version) ready"
        case .unsupported(let check): return "claude \(check.version) unsupported"
        case .missing: return "claude not found"
        case .failed: return "claude failed"
        }
    }

    private var tooltip: String {
        switch indicatorState {
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
                Install via `\(SupportedClaudeVersion.installCommand)`, \
                or relaunch Plumage from a terminal so it inherits your shell PATH.
                """
        case .failed(let error):
            return error.detectionMessage
        }
    }

    private var accessibilityLabel: String {
        switch indicatorState {
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

#Preview("StatusBar (ok)") {
    ProjectStatusBar(
        indicatorState: .ok(
            VersionCheck(
                version: SemanticVersion(major: 1, minor: 2, patch: 3),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: true
            )
        )
    )
    .frame(width: 720)
}

#Preview("StatusBar (missing)") {
    ProjectStatusBar(indicatorState: .missing)
        .frame(width: 720)
}
