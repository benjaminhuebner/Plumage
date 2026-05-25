import SwiftUI

struct TerminalInspectorView: View {
    let tabsModel: TerminalTabsModel

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(model: tabsModel)
            ZStack {
                // ZStack-mount every tab so each SwiftTerm-PTY buffer stays
                // alive while hidden — dismantling a tab's NSView would also
                // tear its PTY buffer down. Visibility is opacity-flipped, hit
                // testing and accessibility scoped to the active tab.
                ForEach(tabsModel.tabs) { tab in
                    EmbeddedTerminalView(session: tab.session)
                        .opacity(tab.id == tabsModel.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabsModel.selectedTabID)
                        .accessibilityHidden(tab.id != tabsModel.selectedTabID)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .overlay(alignment: .top) {
            if let session = tabsModel.activeSession,
                case .exited(let code, let reason) = session.state
            {
                ExitBanner(code: code, reason: reason) {
                    session.restart()
                }
            }
        }
        .focusedSceneValue(\.terminalTabs, tabsModel)
    }
}

#Preview {
    let binary = URL(filePath: "/usr/bin/true")
    let session = TerminalClaudeSession(cwd: URL(filePath: "/tmp"), binaryURL: binary)
    let model = TerminalTabsModel(
        cwd: URL(filePath: "/tmp"),
        binaryURL: binary,
        initialSession: session
    )
    return TerminalInspectorView(tabsModel: model)
        .frame(width: 480, height: 600)
}
