import SwiftUI

struct ClaudeDockPanel: View {
    static let preferredWidth: CGFloat = 420
    private static let preferredHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 28

    let session: ClaudeSession
    let indicatorState: StatusIndicatorModel.IndicatorState
    var onRecheck: (() -> Void)?
    @Binding var isOpen: Bool

    @AccessibilityFocusState private var contentFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            DockPanelHeader(session: session, onClose: close)
            content
        }
        // maxHeight, not a fixed height: a window resized below the panel's
        // 560pt would otherwise clip the chat input off-screen.
        .frame(width: Self.preferredWidth)
        .frame(maxHeight: Self.preferredHeight)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        // Finder file-drop lives here, OUTSIDE .glassEffect, on purpose: the
        // glass effect renders its subtree into a compositing layer that
        // swallows AppKit drag-destination delivery, so a .dropDestination (or
        // any registerForDraggedTypes NSView) placed inside the glass never
        // receives the drop. Applied after the glass, it inserts the dropped
        // paths into the chat draft.
        .dropDestination(for: URL.self) { urls, _ in
            // Only accept when the chat input is actually on screen — see
            // `acceptsFileDrop`. Otherwise the drop would write into a
            // draftMessage the MissingClaudeView never shows, a silent black hole.
            guard acceptsFileDrop else { return false }
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            appendDroppedPaths(files)
            return true
        } isTargeted: {
            isDropTargeted = acceptsFileDrop && $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .accessibilityFocused($contentFocused)
        .onAppear { contentFocused = true }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    func close() {
        isOpen = false
    }

    // Mirrors the `content` switch: the chat input (and thus draftMessage) only
    // exists while claude is loading or ready. In the missing/unsupported/failed
    // states MissingClaudeView is shown with no input, so a file drop has nowhere
    // visible to land.
    private var acceptsFileDrop: Bool {
        switch indicatorState {
        case .loading, .ok: return true
        case .missing, .unsupported, .failed: return false
        }
    }

    private func appendDroppedPaths(_ urls: [URL]) {
        let insertion = DroppedFilePaths.insertionText(for: urls)
        guard !insertion.isEmpty else { return }
        let current = session.draftMessage
        if current.isEmpty || current.last?.isWhitespace == true {
            session.draftMessage = current + insertion
        } else {
            session.draftMessage = current + " " + insertion
        }
    }

    @ViewBuilder
    private var content: some View {
        switch indicatorState {
        case .loading, .ok:
            chatContent
        case .missing, .unsupported, .failed:
            MissingClaudeView(state: indicatorState, onRecheck: onRecheck)
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        ChatView(session: session)
            .overlay(alignment: .top) {
                if case .exited(let code, let reason) = session.state {
                    ExitBanner(code: code, reason: reason) {
                        session.restart()
                    }
                }
            }
    }
}

private struct DockPanelHeader: View {
    let session: ClaudeSession
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Decorative: statusText carries the state for VoiceOver.
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if session.awaitingResponse {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Close Claude")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
}

#Preview("Loading") {
    let session = ClaudeSession(
        cwd: URL(filePath: "/tmp"),
        binaryURL: URL(filePath: "/usr/bin/true"),
        stateDirectory: URL(filePath: "/tmp"),
        autoSpawn: false
    )
    return ClaudeDockPanel(
        session: session,
        indicatorState: .loading,
        isOpen: .constant(true)
    )
    .padding(40)
}
