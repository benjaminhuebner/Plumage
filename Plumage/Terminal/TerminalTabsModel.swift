import Foundation
import Observation

@Observable
@MainActor
final class TerminalTabsModel {
    private(set) var tabs: [TerminalTab] = []
    var selectedTabID: UUID?

    private let cwd: URL
    private let binaryURL: URL
    // Shared by the default tab and every ephemeral tab. Typically returns
    // the chat session's ID so terminal reconciles don't adopt it. New
    // ephemeral tabs do NOT exclude other tabs' conversationIDs in v0.1 — if
    // claude rotates a log in tab A while tab B's reconcile fires, tab B may
    // adopt tab A's ID. Follow-up if it shows up in daily use.
    private var sharedExcludedSessionIDs: () -> Set<String>

    init(
        cwd: URL,
        binaryURL: URL,
        initialSession: TerminalClaudeSession,
        excludedSessionIDs: @escaping () -> Set<String> = { [] }
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.sharedExcludedSessionIDs = excludedSessionIDs
        let firstTab = TerminalTab(session: initialSession, title: "Terminal 1")
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
    }

    var activeSession: TerminalClaudeSession? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.id == id })?.session
    }

    var canCloseActiveTab: Bool { tabs.count > 1 }

    func addTab() {
        let session = TerminalClaudeSession(
            cwd: cwd,
            binaryURL: binaryURL,
            excludedSessionIDs: sharedExcludedSessionIDs,
            persistConversationID: false
        )
        session.attach()
        let tab = TerminalTab(session: session, title: "Terminal \(tabs.count + 1)")
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(id: UUID) {
        // Guard the last-tab rule here too so callers can ignore canCloseActiveTab
        // and rely on the model to defensively no-op.
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs[idx]
        removed.session.stop()
        tabs.remove(at: idx)
        reindexTitles()
        if selectedTabID == id {
            // Prefer left neighbor (idx-1); fall back to right (which is now at
            // the removed position) if the closed tab was the leftmost.
            let neighborIdx = idx > 0 ? idx - 1 : 0
            selectedTabID = tabs[neighborIdx].id
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedTabID = tabs[index].id
    }

    func stopAll() {
        for tab in tabs { tab.session.stop() }
    }

    func setSharedExcludedSessionIDs(_ provider: @escaping () -> Set<String>) {
        sharedExcludedSessionIDs = provider
    }

    private func reindexTitles() {
        for index in tabs.indices {
            tabs[index].title = "Terminal \(index + 1)"
        }
    }
}
