import SwiftUI

struct ChatView: View {
    @Bindable var session: ClaudeSession

    var body: some View {
        VStack(spacing: 0) {
            messageList
            ChatInputField(
                text: $session.draftMessage,
                canSend: canSend,
                onSend: send
            )
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(scrollAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            // Scroll only when a genuinely new message lands at the bottom —
            // keying on `.last?.id` instead of `.count` avoids stacking an
            // animated scroll on every array mutation (e.g. trim-to-cap or
            // mid-array status edits) during rapid Claude streaming.
            .onChange(of: session.messages.last?.id) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(scrollAnchorID, anchor: .bottom)
            }
        }
    }

    private var canSend: Bool {
        if case .running = session.state, !session.awaitingResponse {
            return true
        }
        return false
    }

    private func send() {
        let text = session.draftMessage
        session.draftMessage = ""
        Task { [weak session] in await session?.send(text) }
    }

    private let scrollAnchorID = "chat-bottom-anchor"
}

#Preview("Empty session") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        stateDirectory: URL(filePath: "/tmp"),
        autoSpawn: false
    )
    session.start()
    session.handleEvent(.systemInit(sessionID: "preview-session"))
    return ChatView(session: session)
        .frame(width: 460, height: 600)
}

#Preview("Conversation") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        stateDirectory: URL(filePath: "/tmp"),
        autoSpawn: false
    )
    session.start()
    session.handleEvent(.systemInit(sessionID: "preview-session"))
    session.handleEvent(.assistant([.text("Hi! How can I help?")]))
    return ChatView(session: session)
        .frame(width: 460, height: 600)
}
