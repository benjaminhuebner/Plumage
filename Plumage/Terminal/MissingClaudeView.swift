import SwiftUI

struct MissingClaudeView: View {
    let state: StatusIndicatorModel.IndicatorState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(headline, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(diagnostic)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Install with:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SupportedClaudeVersion.installCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 6))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headline: String {
        switch state {
        case .loading, .ok:
            return "claude check in progress"
        case .unsupported:
            return "claude version not supported"
        case .missing:
            return "claude not found"
        case .failed:
            return "claude check failed"
        }
    }

    private var icon: String {
        switch state {
        case .unsupported: return "exclamationmark.triangle.fill"
        case .missing, .failed: return "xmark.octagon.fill"
        case .loading, .ok: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .unsupported: return .yellow
        case .missing, .failed: return .red
        case .loading, .ok: return .secondary
        }
    }

    private var diagnostic: String {
        switch state {
        case .loading:
            return "Detecting `claude` binary…"
        case .ok(let check):
            return "Found \(check.version) at \(check.binaryURL.path)."
        case .unsupported(let check):
            return """
                Found \(check.version) at \(check.binaryURL.path). \
                Supported range: \(SupportedClaudeVersion.supportedRangeDescription).
                """
        case .missing:
            return """
                Searched \(SupportedClaudeVersion.searchPathDescription).

                If claude is installed but not found, relaunch Plumage from a \
                terminal so it inherits your shell's PATH.
                """
        case .failed(let error):
            return error.detectionMessage
        }
    }
}

#Preview("Missing") {
    MissingClaudeView(state: .missing)
        .frame(width: 420, height: 360)
}

#Preview("Unsupported") {
    MissingClaudeView(
        state: .unsupported(
            VersionCheck(
                version: SemanticVersion(major: 0, minor: 9, patch: 0),
                binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
                inSupportedRange: false
            )
        )
    )
    .frame(width: 420, height: 360)
}

#Preview("Failed") {
    MissingClaudeView(
        state: .failed(.nonZeroExit(code: 127, stderr: "command not found: claude"))
    )
    .frame(width: 420, height: 360)
}
