import SwiftUI

struct ChatMessageView: View {
    let message: ClaudeSession.ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            switch message.role {
            case .user:
                Spacer(minLength: 40)
                bubble
            case .assistant:
                bubble
                Spacer(minLength: 40)
            case .system:
                Spacer(minLength: 0)
                systemBubble
                Spacer(minLength: 0)
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleBackground, in: .rect(cornerRadius: 10))
    }

    private var systemBubble: some View {
        Text(message.text)
            .font(.caption.italic())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private var bubbleBackground: AnyShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .assistant:
            return AnyShapeStyle(.quaternary)
        case .system:
            return AnyShapeStyle(Color.clear)
        }
    }
}

#Preview("Conversation") {
    VStack(spacing: 8) {
        ChatMessageView(
            message: .init(
                id: UUID(), role: .system,
                text: "Session ready (id: abc-123)",
                timestamp: .now
            )
        )
        ChatMessageView(
            message: .init(
                id: UUID(), role: .user,
                text: "What does this project do?",
                timestamp: .now
            )
        )
        ChatMessageView(
            message: .init(
                id: UUID(), role: .assistant,
                text:
                    "Plumage is a native macOS GUI for Claude Code workflows — "
                    + "Kanban issues, embedded agent session, integrated editor, "
                    + "local PR view.",
                timestamp: .now
            )
        )
        ChatMessageView(
            message: .init(
                id: UUID(), role: .assistant,
                text: "🔧 Tool: Bash",
                timestamp: .now
            )
        )
    }
    .padding()
    .frame(width: 460)
}
