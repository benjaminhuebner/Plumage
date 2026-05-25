import Foundation
import Observation

@Observable
@MainActor
final class TerminalTabsModel {
    private(set) var tabs: [TerminalTab] = []
    var selectedTabID: UUID?

    let cwd: URL
    let binaryURL: URL
    // Injected by ProjectWindow — currently returns the chat session's
    // conversationID so terminal reconcile never adopts it. With every
    // tab running ephemeral, reconcile is structurally disabled (its
    // guard fires on sessionIDStoreURL == nil), so this closure is dead
    // wiring today. It's kept in place so a future, narrower persistence
    // story can re-arm reconcile without having to re-thread the chat
    // exclude back through the model.
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
        let firstTab = TerminalTab(session: initialSession, title: Self.title(for: 0))
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
    }

    // Index 0 is the sticky main terminal — own name. Additional tabs are
    // numbered by their 1-based index to match the ⌘1/⌘2/⌘3 shortcuts.
    private static func title(for index: Int) -> String {
        index == 0 ? "Main Terminal" : "Terminal \(index + 1)"
    }

    // The sticky main tab. closeTab refuses to remove index 0, so this is
    // safe as a non-optional. runWorkflow injects here regardless of which
    // tab the user has selected — workflow inputs (/plan, /implement) belong
    // to the project, not to an ad-hoc secondary conversation.
    var mainSession: TerminalClaudeSession {
        precondition(!tabs.isEmpty, "main tab is sticky and must always exist")
        return tabs[0].session
    }

    var activeSession: TerminalClaudeSession? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.id == id })?.session
    }

    // The tab at index 0 is the main terminal — sticky, never closable.
    // canCloseActiveTab is the keyboard-shortcut convenience; per-tab UI
    // queries canClose(_:) instead.
    var canCloseActiveTab: Bool {
        guard let id = selectedTabID else { return false }
        return canClose(id)
    }

    func canClose(_ tabID: UUID) -> Bool {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        return idx > 0
    }

    func addTab() {
        // Every tab — main and extras — is ephemeral, see init's note.
        let session = TerminalClaudeSession(
            cwd: cwd,
            binaryURL: binaryURL,
            excludedSessionIDs: sharedExcludedSessionIDs,
            persistConversationID: false
        )
        let tab = TerminalTab(session: session, title: Self.title(for: tabs.count))
        tabs.append(tab)
        // attach() is intentionally NOT called here — SwiftTermBridge.makeNSView
        // owns the attach lifecycle and flips state to .starting right before
        // startProcess(). Calling attach() pre-mount would leave the session
        // in .starting with no PTY behind it if the inspector never opens.
        selectedTabID = tab.id
    }

    func closeTab(id: UUID) {
        // Defensive no-op for the main terminal — its slot is sticky.
        guard canClose(id) else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs[idx]
        removed.session.stop()
        tabs.remove(at: idx)
        reindexTitles()
        if selectedTabID == id {
            // Prefer left neighbor — closable tabs always start at idx > 0,
            // so the left neighbor always exists.
            selectedTabID = tabs[idx - 1].id
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
        // Propagate to existing tabs so the initial main tab also picks up
        // the chat-exclude that the caller wires post-init. Currently dead
        // wiring because reconcile is disabled for ephemeral sessions, but
        // kept symmetric with addTab's closure plumbing.
        for tab in tabs {
            tab.session.setExcludedSessionIDs(provider)
        }
    }

    private func reindexTitles() {
        for index in tabs.indices {
            tabs[index].title = Self.title(for: index)
        }
    }
}
