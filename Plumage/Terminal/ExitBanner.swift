import SwiftUI

struct ExitBanner: View {
    let code: Int32
    let reason: ClaudeSession.ExitReason
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Button("Restart", action: onRestart)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var icon: String {
        switch reason {
        case .userClosed: return "checkmark.circle.fill"
        case .crashed: return "exclamationmark.triangle.fill"
        case .killed: return "stop.circle.fill"
        }
    }

    private var tint: Color {
        switch reason {
        case .userClosed: return .secondary
        case .crashed: return .red
        case .killed: return .orange
        }
    }

    private var label: String {
        let reasonText: String
        switch reason {
        case .userClosed: reasonText = "userClosed"
        case .crashed: reasonText = "crashed"
        case .killed: reasonText = "killed"
        }
        return "Session ended — exit \(code), \(reasonText)"
    }
}

#Preview("UserClosed") {
    ExitBanner(code: 0, reason: .userClosed, onRestart: {})
        .frame(width: 480)
        .padding()
}

#Preview("Crashed") {
    ExitBanner(code: 1, reason: .crashed, onRestart: {})
        .frame(width: 480)
        .padding()
}

#Preview("Killed") {
    ExitBanner(code: 137, reason: .killed, onRestart: {})
        .frame(width: 480)
        .padding()
}
