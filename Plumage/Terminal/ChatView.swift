import SwiftUI

struct ChatView: View {
    let session: ClaudeSession
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputField(
                text: $draft,
                canSend: canSend,
                onSend: send
            )
            .background(.bar)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    statusHeader
                    ForEach(session.messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(scrollAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: session.messages.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(scrollAnchorID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if session.awaitingResponse {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer(minLength: 0)
            Button {
                openInTerminal()
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open claude in Terminal.app (full REPL)")
        }
        .padding(.bottom, 4)
    }

    private func openInTerminal() {
        let escapedPath = session.cwd.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Terminal"
                activate
                set newTab to do script "cd \\"\(escapedPath)\\" && claude"
                set frontmost of window 1 to true
            end tell
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    private var statusText: String {
        switch session.state {
        case .idle: return "idle"
        case .starting: return "connecting…"
        case .running: return "running"
        case .exited(let code, _): return "ended (exit \(code))"
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .idle: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .exited: return .red
        }
    }

    private var canSend: Bool {
        if case .running = session.state, !session.awaitingResponse {
            return true
        }
        return false
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await session.send(text) }
    }

    private let scrollAnchorID = "chat-bottom-anchor"
}

#Preview("Empty session") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
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
        autoSpawn: false
    )
    session.start()
    session.handleEvent(.systemInit(sessionID: "preview-session"))
    session.handleEvent(.assistant([.text("Hi! How can I help?")]))
    return ChatView(session: session)
        .frame(width: 460, height: 600)
}
