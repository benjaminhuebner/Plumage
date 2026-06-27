import Foundation
import Observation

@Observable
@MainActor
final class TerminalTabsModel {
    private(set) var tabs: [TerminalTab] = []
    var selectedTabID: UUID?

    let cwd: URL
    let binaryURL: URL
    // Per-project model overrides. ProjectWindow refreshes this on config
    // reload so a newly-spawned tab picks up the latest picker selection;
    // already-running tabs keep their original model (the spec calls out
    // "changes only take effect for new sessions/tabs").
    var modelsConfig: ModelsConfig?
    var effortsConfig: EffortsConfig?
    // Injected by ProjectWindow — currently returns the chat session's
    // conversationID so terminal reconcile never adopts it. With every
    // tab running ephemeral, reconcile is structurally disabled (its
    // guard fires on sessionIDStoreURL == nil), so this closure is dead
    // wiring today. It's kept in place so a future, narrower persistence
    // story can re-arm reconcile without having to re-thread the chat
    // exclude back through the model.
    private var sharedExcludedSessionIDs: @MainActor () -> Set<String>
    // Fires after a non-main tab has been removed from `tabs`. ProjectWindow
    // registers a handler that cancels its in-flight workflowTask when the
    // workflow tab is closed mid-inject — without it, the task strands for
    // up to ~850ms inside its bodyDelay sleep, holding the dead session.
    var onTabClosed: (@MainActor (TerminalTab) -> Void)?

    init(
        cwd: URL,
        binaryURL: URL,
        initialSession: TerminalClaudeSession,
        modelsConfig: ModelsConfig? = nil,
        effortsConfig: EffortsConfig? = nil,
        excludedSessionIDs: @escaping @MainActor () -> Set<String> = { [] }
    ) {
        self.cwd = cwd
        self.binaryURL = binaryURL
        self.modelsConfig = modelsConfig
        self.effortsConfig = effortsConfig
        self.sharedExcludedSessionIDs = excludedSessionIDs
        let firstTab = TerminalTab(session: initialSession, title: Self.title(for: 0))
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
        installExclusionClosure(on: initialSession)
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
            modelChoice: modelsConfig?.terminalsResolved ?? ModelsConfig.terminalsDefault,
            effortChoice: effortsConfig?.terminalsResolved ?? EffortsConfig.terminalsDefault,
            excludedSessionIDs: sharedExcludedSessionIDs,
            persistConversationID: false
        )
        let tab = TerminalTab(session: session, title: Self.title(for: tabs.count))
        tabs.append(tab)
        installExclusionClosure(on: session)
        // attach() is intentionally NOT called here — SwiftTermBridge.makeNSView
        // owns the attach lifecycle and flips state to .starting right before
        // startProcess(). Calling attach() pre-mount would leave the session
        // in .starting with no PTY behind it if the inspector never opens.
        selectedTabID = tab.id
    }

    // A worktree implement run carries a title suffix so the tab is
    // distinguishable; dedupe must match both forms or a re-click would
    // spawn a duplicate normal tab next to the worktree one.
    static func worktreeTitle(base: String) -> String {
        "\(base) — worktree"
    }

    func findWorkflowTab(action: WorkflowAction, slug: String) -> TerminalTab? {
        let title = action.tabTitle(slug: slug)
        let worktreeTitle = Self.worktreeTitle(base: title)
        return tabs.first(where: { $0.title == title || $0.title == worktreeTitle })
    }

    @discardableResult
    func addWorkflowTab(
        action: WorkflowAction,
        slug: String,
        type: IssueType,
        override: WorkflowOverride? = nil,
        worktreeRoot: URL? = nil
    ) -> TerminalTab {
        let resolved =
            modelsConfig?.workflowResolved(action, type: type)
            ?? ModelsConfig.slotDefault(for: action.modelSlot)
        let resolvedEffort =
            effortsConfig?.workflowResolved(action, type: type)
            ?? EffortsConfig.slotDefault(for: action.modelSlot)
        let permMode = override?.permissionMode ?? action.permissionMode
        // The signal dir is created once at launch by RunAlertCoordinator.start(),
        // so the default notificationSignalURL needs no dir-create here.
        let session = TerminalClaudeSession(
            cwd: worktreeRoot ?? cwd,
            binaryURL: binaryURL,
            modelChoice: resolved,
            effortChoice: resolvedEffort,
            excludedSessionIDs: sharedExcludedSessionIDs,
            persistConversationID: false,
            permissionMode: permMode
        )
        // Plan/review self-exit posts a completion banner; implement is excluded
        // because its run-state path already banners — wiring it would double-fire.
        if action == .plan || action == .review {
            let projectRoot = cwd
            let issueSlug = slug
            let bannerBody = action == .plan ? "Plan finished" : "Review finished"
            session.onProcessFinished = {
                Task { @MainActor in
                    let title =
                        await RunCompletionNotifier.issueTitle(root: projectRoot, slug: issueSlug)
                        ?? issueSlug
                    RunCompletionNotifier.shared.runFinished(
                        title: title, slug: issueSlug, projectRoot: projectRoot, body: bannerBody)
                }
            }
        }
        let baseTitle = action.tabTitle(slug: slug)
        let tab = TerminalTab(
            session: session,
            title: worktreeRoot != nil ? Self.worktreeTitle(base: baseTitle) : baseTitle,
            isWorkflow: true
        )
        tabs.append(tab)
        installExclusionClosure(on: session)
        selectedTabID = tab.id
        return tab
    }

    func closeTab(id: UUID) {
        // Single scan: firstIndex covers both the "exists?" and "is closable?"
        // checks. idx > 0 enforces the main-tab sticky invariant.
        guard let idx = tabs.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        let removed = tabs[idx]
        removed.session.stop()
        tabs.remove(at: idx)
        reindexTitles()
        if selectedTabID == id {
            // Prefer left neighbor — closable tabs always start at idx > 0,
            // so the left neighbor always exists.
            selectedTabID = tabs[idx - 1].id
        }
        onTabClosed?(removed)
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedTabID = tabs[index].id
    }

    func stopAll() {
        for tab in tabs { tab.session.stop() }
    }

    func setSharedExcludedSessionIDs(_ provider: @escaping @MainActor () -> Set<String>) {
        sharedExcludedSessionIDs = provider
        // The per-tab closure already reads `sharedExcludedSessionIDs` lazily
        // via the captured `self`, so the chat provider is picked up
        // automatically on the next reconcile. We still re-install to cover
        // the (defensive) case where a caller had swapped the closure out
        // from underneath us — the install resets each tab's closure to the
        // model-aware one that exposes chat + all-tab-IDs together.
        for tab in tabs {
            installExclusionClosure(on: tab.session)
        }
    }

    // Each tab's reconcile-exclude set = chat-provider's set ∪ every tab's
    // conversationID. Reconcile already skips the session's own ID, so we
    // don't need to filter self out here. Currently dead wiring because all
    // tabs are ephemeral and reconcile early-returns on sessionIDStoreURL ==
    // nil — but defense-in-depth for a future re-armed reconcile path
    private func installExclusionClosure(on session: TerminalClaudeSession) {
        session.setExcludedSessionIDs { [weak self] in
            guard let self else { return [] }
            // Seed capacity to avoid n re-hashes on each FSEvents-driven
            // reconcile when tab count grows. The +4 is slack for chat-side
            // IDs in `sharedExcludedSessionIDs`; oversizing slightly is
            // cheaper than a re-hash partway through the merge.
            var ids = Set<String>(minimumCapacity: self.tabs.count + 4)
            for tab in self.tabs {
                ids.insert(tab.session.conversationID)
            }
            ids.formUnion(self.sharedExcludedSessionIDs())
            return ids
        }
    }

    // Workflow tabs hold a user-meaningful title ("Plan: <slug>") that must
    // not be clobbered by a sibling tab close. Only generic ("Terminal N")
    // tabs are reindexed. Without this guard, any closeTab would overwrite
    // every workflow tab's title and break findWorkflowTab's exact-match
    // lookup, causing a duplicate tab on the next workflow click.
    private func reindexTitles() {
        for index in tabs.indices where !tabs[index].isWorkflow {
            tabs[index].title = Self.title(for: index)
        }
    }
}
