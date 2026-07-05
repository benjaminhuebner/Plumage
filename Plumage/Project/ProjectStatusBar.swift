import SwiftUI

struct ProjectStatusBar: View {
    let indicatorState: StatusIndicatorModel.IndicatorState
    let usageModel: ClaudeUsageModel?
    let statusModel: ClaudeStatusModel?
    let repoState: RepoState
    let gitModel: ProjectGitModel?
    var banner: String?
    var queueEntries: [QueueEntryDisplay]
    var onCancelQueued: (String) -> Void
    var chatIsWorking: Bool
    var onToggleChat: (() -> Void)?

    init(
        indicatorState: StatusIndicatorModel.IndicatorState,
        usageModel: ClaudeUsageModel? = nil,
        statusModel: ClaudeStatusModel? = nil,
        repoState: RepoState = .notARepo,
        gitModel: ProjectGitModel? = nil,
        banner: String? = nil,
        queueEntries: [QueueEntryDisplay] = [],
        onCancelQueued: @escaping (String) -> Void = { _ in },
        chatIsWorking: Bool = false,
        onToggleChat: (() -> Void)? = nil
    ) {
        self.indicatorState = indicatorState
        self.usageModel = usageModel
        self.statusModel = statusModel
        self.repoState = repoState
        self.gitModel = gitModel
        self.banner = banner
        self.queueEntries = queueEntries
        self.onCancelQueued = onCancelQueued
        self.chatIsWorking = chatIsWorking
        self.onToggleChat = onToggleChat
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                // Not fixedSize: a long branch name must middle-truncate in a
                // tight column instead of pushing the bar past its edge.
                ProjectBranchIndicator(state: repoState, gitModel: gitModel)
                    .layoutPriority(0)
                if let statusModel {
                    StatusPageButton(model: statusModel)
                        .fixedSize()
                        .layoutPriority(0)
                }
                HStack(spacing: 6) {
                    statusDot
                        .accessibilityHidden(true)
                    // Banner messages take priority over the static indicator
                    // label — for the ~3 s window the user sees the rejection
                    // reason instead of "claude X ready".
                    Text(banner ?? label)
                        .font(.caption)
                        .foregroundStyle(banner == nil ? .secondary : .primary)
                        .accessibilityIdentifier(banner == nil ? "indicator-label" : "drop-banner")
                        .lineLimit(1)
                }
                // Vertical-only: in a tight column the label tail-truncates
                // (full text stays reachable via the .help tooltip below).
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                if let usageModel {
                    usagePill(usageModel: usageModel)
                        .fixedSize()
                        .layoutPriority(0)
                }
                Spacer(minLength: 0)
                if !queueEntries.isEmpty {
                    QueueStatusButton(entries: queueEntries, onCancel: onCancelQueued)
                        .fixedSize()
                        .layoutPriority(0)
                }
                if let onToggleChat {
                    StatusBarChatButton(isWorking: chatIsWorking, action: onToggleChat)
                        .fixedSize()
                        .layoutPriority(0)
                }
            }
            .padding(.leading, 12)
            // The window's corner curve cuts into the bar's trailing end;
            // extra padding keeps controls out of the curve.
            .padding(.trailing, 20)
            // Leading-anchored: if the row ever overflows, the spacer side
            // clips — never the branch pill at the leading edge.
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            // Solid fill, not .bar: bar material is navigation-layer chrome;
            // this strip sits on the content layer below the detail pane.
            .background(.background.secondary)
            .help(banner ?? tooltip)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func usagePill(usageModel: ClaudeUsageModel) -> some View {
        if usageModel.isLoggedOut {
            LoggedOutHintButton()
        } else {
            UsageButton(model: usageModel)
        }
    }

    // Decorative: the adjacent label text carries the state for VoiceOver.
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
}

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.6 : (pulsing ? 1.0 : 0.4))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear {
                guard !reduceMotion else { return }
                pulsing = true
            }
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
