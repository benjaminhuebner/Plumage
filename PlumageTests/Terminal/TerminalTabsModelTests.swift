import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("TerminalTabsModel")
struct TerminalTabsModelTests {
    @Test("addTab grows tabs and selects the new one")
    func addTabAppendsAndSelects() {
        let model = makeModel()
        let initialID = model.tabs[0].id
        #expect(model.tabs.count == 1)
        #expect(model.tabs[0].title == "Main Terminal")
        #expect(model.selectedTabID == initialID)

        model.addTab()

        #expect(model.tabs.count == 2)
        #expect(model.tabs[1].title == "Terminal 2")
        #expect(model.selectedTabID == model.tabs[1].id)
    }

    @Test("closeTab reindexes remaining titles")
    func closeTabReindexes() {
        let model = makeModel()
        model.addTab()
        model.addTab()
        #expect(model.tabs.map(\.title) == ["Main Terminal", "Terminal 2", "Terminal 3"])

        let middleID = model.tabs[1].id
        model.closeTab(id: middleID)

        #expect(model.tabs.count == 2)
        #expect(model.tabs.map(\.title) == ["Main Terminal", "Terminal 2"])
    }

    @Test("the main terminal at index 0 is never closable")
    func mainTerminalIsSticky() {
        let model = makeModel()
        let mainID = model.tabs[0].id
        #expect(model.canClose(mainID) == false)
        #expect(model.canCloseActiveTab == false)

        // Single-tab world.
        model.closeTab(id: mainID)
        #expect(model.tabs.count == 1)
        #expect(model.tabs[0].id == mainID)

        // Multi-tab world: main still sticky.
        model.addTab()
        model.addTab()
        #expect(model.canClose(mainID) == false)
        model.closeTab(id: mainID)
        #expect(model.tabs.count == 3)
        #expect(model.tabs[0].id == mainID)
    }

    @Test("non-main tabs are closable and selection falls back to the left")
    func closingNonMainPicksLeftNeighbor() {
        let model = makeModel()
        model.addTab()
        model.addTab()
        let mainID = model.tabs[0].id
        let middleID = model.tabs[1].id
        let lastID = model.tabs[2].id

        #expect(model.canClose(lastID))
        // Active = last (set by addTab). Closing it picks middle.
        model.closeTab(id: lastID)
        #expect(model.selectedTabID == middleID)

        // Now active = middle. Closing it picks main.
        model.closeTab(id: middleID)
        #expect(model.selectedTabID == mainID)
        #expect(model.tabs.count == 1)
    }

    @Test("canCloseActiveTab follows the selection")
    func canCloseActiveTabFollowsSelection() {
        let model = makeModel()
        model.addTab()
        let mainID = model.tabs[0].id
        let extraID = model.tabs[1].id

        // Selection just landed on the extra tab via addTab().
        #expect(model.selectedTabID == extraID)
        #expect(model.canCloseActiveTab)

        model.selectTab(at: 0)
        #expect(model.selectedTabID == mainID)
        #expect(model.canCloseActiveTab == false)
    }

    @Test("stopAll transitions every attached session to exited")
    func stopAllStopsEverySession() {
        let model = makeModel()
        // Production: SwiftTermBridge.makeNSView calls attach() per tab when
        // its EmbeddedTerminalView mounts. There's no bridge in tests, so
        // simulate the mount by calling attach() on each session ourselves.
        model.addTab()
        model.addTab()
        for tab in model.tabs { tab.session.attach() }
        for tab in model.tabs {
            #expect(isStarting(tab.session.state))
        }

        model.stopAll()

        for tab in model.tabs {
            #expect(isExited(tab.session.state))
        }
    }

    @Test("stopAll leaves unattached (.idle) sessions untouched")
    func stopAllSkipsIdleSessions() {
        let model = makeModel()
        // Tab created via addTab() never gets attach() unless the bridge
        // mounts. stopAll() must not crash on .idle sessions — they simply
        // remain .idle (TerminalClaudeSession.stop early-returns for .idle).
        model.addTab()
        for tab in model.tabs {
            #expect(isIdle(tab.session.state))
        }

        model.stopAll()

        for tab in model.tabs {
            #expect(isIdle(tab.session.state))
        }
    }

    @Test("mainSession always returns the index-0 tab session")
    func mainSessionReturnsStickyTab() {
        let model = makeModel()
        let mainSession = model.tabs[0].session
        #expect(model.mainSession === mainSession)

        model.addTab()
        model.addTab()
        // Even after adding tabs (and addTab selecting the new one),
        // mainSession stays pinned to index 0.
        #expect(model.mainSession === mainSession)
        #expect(model.activeSession !== mainSession)
    }

    @Test("every tab has its own fresh conversationID")
    func tabsHaveDistinctConversationIDs() {
        let model = makeModel()
        let mainID = model.mainSession.conversationID
        model.addTab()
        model.addTab()
        let ids = model.tabs.map(\.session.conversationID)
        #expect(ids.count == Set(ids).count)
        #expect(ids[0] == mainID)
        // All tabs are ephemeral — none should persist to disk under the
        // current policy (see TerminalTabsModel.init's note).
        for tab in model.tabs {
            #expect(tab.session.conversationID.count == 36)  // UUID format
        }
    }

    @Test("findWorkflowTab returns nil when no matching title exists")
    func findWorkflowTabMissing() {
        let model = makeModel()
        #expect(model.findWorkflowTab(action: .plan, slug: "any-slug") == nil)
    }

    @Test("findWorkflowTab matches an existing tab by exact title")
    func findWorkflowTabExisting() {
        let model = makeModel()
        let created = model.addWorkflowTab(action: .plan, slug: "walking-skeleton")
        let found = model.findWorkflowTab(action: .plan, slug: "walking-skeleton")
        #expect(found?.id == created.id)
        // Different action / slug => no match (title differs).
        #expect(model.findWorkflowTab(action: .implement, slug: "walking-skeleton") == nil)
        #expect(model.findWorkflowTab(action: .plan, slug: "other-slug") == nil)
    }

    @Test("addWorkflowTab appends with the correct title and selects it")
    func addWorkflowTabAppendsAndSelects() {
        let model = makeModel()
        let mainID = model.tabs[0].id
        let tab = model.addWorkflowTab(action: .implement, slug: "00038-workflow-tabs-per-action")
        #expect(model.tabs.count == 2)
        #expect(model.tabs[1].id == tab.id)
        #expect(tab.title == "Implement: 00038-workflow-tabs-per-action")
        #expect(model.selectedTabID == tab.id)
        // Main tab is not displaced.
        #expect(model.tabs[0].id == mainID)
    }

    @Test("plan tab with default model uses --permission-mode plan and no --model flag")
    func addWorkflowTabPlanDefaultUsesPlanMode() {
        let model = makeModel()
        let tab = model.addWorkflowTab(action: .plan, slug: "x")
        let cmd = tab.session.shellSpawnArgs()[1]
        #expect(cmd.contains("'--permission-mode' 'plan'"))
        #expect(!cmd.contains("--model"))
    }

    @Test("plan tab keeps plan mode regardless of chosen model")
    func addWorkflowTabPlanKeepsPlanModeForAnyModel() {
        let model = makeModel()
        // Permission mode is decoupled from the model: a non-default model
        // choice for Plan still spawns with --permission-mode plan.
        model.modelsConfig = ModelsConfig(plan: .sonnet)
        let tab = model.addWorkflowTab(action: .plan, slug: "x")
        let cmd = tab.session.shellSpawnArgs()[1]
        #expect(cmd.contains("'--permission-mode' 'plan'"))
        #expect(cmd.contains("'--model' 'sonnet'"))
    }

    @Test("implement tab always uses acceptEdits regardless of model")
    func addWorkflowTabImplementUsesAcceptEdits() {
        let model = makeModel()
        model.modelsConfig = ModelsConfig(implement: .sonnet)
        let tab = model.addWorkflowTab(action: .implement, slug: "x")
        let cmd = tab.session.shellSpawnArgs()[1]
        #expect(cmd.contains("'--permission-mode' 'acceptEdits'"))
    }

    @Test("workflow tabs are closable (only the main tab is sticky)")
    func workflowTabsAreClosable() {
        let model = makeModel()
        let tab = model.addWorkflowTab(action: .review, slug: "rev")
        #expect(model.canClose(tab.id))
    }

    @Test("each tab's exclude set contains every tab's conversationID")
    func excludeClosureCoversAllTabIDs() {
        let chatID = "chat-\(UUID().uuidString.lowercased())"
        let model = makeModel(excludedSessionIDs: { [chatID] })
        let mainID = model.tabs[0].session.conversationID
        let extraTab = model.addWorkflowTab(action: .plan, slug: "x")
        let extraID = extraTab.session.conversationID
        let workflowTab = model.addWorkflowTab(action: .review, slug: "y")
        let workflowID = workflowTab.session.conversationID

        // Every tab's closure must report every tab's ID plus the shared
        // chat ID. The closure also returns the tab's own ID, which is fine
        // because reconcileSessionFromDisk filters self separately.
        for tab in model.tabs {
            let excluded = tab.session.currentExcludedSessionIDs()
            #expect(excluded.contains(chatID), "chat exclude must propagate")
            #expect(excluded.contains(mainID), "main tab ID must be excluded")
            #expect(excluded.contains(extraID), "first workflow tab ID must be excluded")
            #expect(excluded.contains(workflowID), "second workflow tab ID must be excluded")
        }
    }

    @Test("workflow orchestration: repeat addWorkflowTab is gated by findWorkflowTab")
    func workflowFindOrCreateContract() {
        let model = makeModel()
        // First click → no existing tab, addWorkflowTab creates it.
        #expect(model.findWorkflowTab(action: .plan, slug: "abc") == nil)
        let created = model.addWorkflowTab(action: .plan, slug: "abc")

        // Second click for the same action+slug → find returns the same tab,
        // caller never calls add again. Total tabs stays at 2 (main + plan).
        let found = model.findWorkflowTab(action: .plan, slug: "abc")
        #expect(found?.id == created.id)
        #expect(model.tabs.count == 2)

        // A different action for the same slug is still a new tab (3 total).
        #expect(model.findWorkflowTab(action: .implement, slug: "abc") == nil)
        model.addWorkflowTab(action: .implement, slug: "abc")
        #expect(model.tabs.count == 3)
    }

    @Test("workflow orchestration: main tab session stays untouched")
    func workflowDoesNotTouchMainSession() {
        let model = makeModel()
        let mainSession = model.tabs[0].session
        #expect(isIdle(mainSession.state))
        #expect(mainSession.pendingInput.isEmpty)

        model.addWorkflowTab(action: .plan, slug: "x")
        model.addWorkflowTab(action: .implement, slug: "y")
        model.addWorkflowTab(action: .review, slug: "z")

        // After three workflow tabs, the main session is still idle with an
        // empty pendingInput buffer — no slash command was injected there.
        #expect(isIdle(mainSession.state))
        #expect(mainSession.pendingInput.isEmpty)
    }

    @Test("closing a generic tab does not clobber a workflow tab's title")
    func closeGenericPreservesWorkflowTitle() {
        let model = makeModel()
        // Layout: [main, Plan: abc, Terminal 3 (generic)]
        let workflowTab = model.addWorkflowTab(action: .plan, slug: "abc")
        let originalTitle = workflowTab.title
        model.addTab()
        let genericID = model.tabs[2].id
        #expect(model.tabs[1].title == originalTitle)

        model.closeTab(id: genericID)

        // The workflow tab must keep its title — otherwise findWorkflowTab's
        // exact-match lookup fails on the next click and a duplicate tab
        // gets created.
        #expect(model.tabs.count == 2)
        #expect(model.tabs[1].title == originalTitle)
        #expect(model.findWorkflowTab(action: .plan, slug: "abc")?.id == workflowTab.id)
    }

    @Test("closeTab fires onTabClosed with the removed workflow tab")
    func onTabClosedFiresForWorkflowTab() {
        let model = makeModel()
        let workflowTab = model.addWorkflowTab(action: .plan, slug: "x")
        var closed: TerminalTab?
        model.onTabClosed = { closed = $0 }

        model.closeTab(id: workflowTab.id)

        #expect(closed?.id == workflowTab.id)
        #expect(closed?.isWorkflow == true)
    }

    @Test("closeTab does not fire onTabClosed for the sticky main tab")
    func onTabClosedSkipsMainTab() {
        let model = makeModel()
        var fired = false
        model.onTabClosed = { _ in fired = true }

        model.closeTab(id: model.tabs[0].id)  // no-op, main is sticky

        #expect(!fired)
    }

    @Test("setSharedExcludedSessionIDs propagates the chat exclude into every tab")
    func setSharedExcludedSessionIDsPropagates() {
        let model = makeModel()
        model.addWorkflowTab(action: .plan, slug: "x")
        let chatID = "chat-\(UUID().uuidString.lowercased())"
        model.setSharedExcludedSessionIDs { [chatID] }
        for tab in model.tabs {
            #expect(tab.session.currentExcludedSessionIDs().contains(chatID))
        }
    }

    @Test("selectTab is bounds-safe")
    func selectTabIsBoundsSafe() {
        let model = makeModel()
        let onlyID = model.tabs[0].id

        model.selectTab(at: -1)
        #expect(model.selectedTabID == onlyID)
        model.selectTab(at: 99)
        #expect(model.selectedTabID == onlyID)

        model.addTab()
        let secondID = model.tabs[1].id

        model.selectTab(at: 0)
        #expect(model.selectedTabID == onlyID)
        model.selectTab(at: 1)
        #expect(model.selectedTabID == secondID)
        model.selectTab(at: 2)
        #expect(model.selectedTabID == secondID)
    }

    // MARK: - Models config threading

    @Test("addTab picks up models.terminals from current config")
    func addTabUsesTerminalsModel() {
        let model = makeModel()
        model.modelsConfig = ModelsConfig(terminals: .sonnet)
        model.addTab()
        #expect(model.tabs.last?.session.modelChoice == .sonnet)
    }

    @Test("addWorkflowTab picks up models.<action> per workflow")
    func addWorkflowTabUsesWorkflowModel() {
        let model = makeModel()
        model.modelsConfig = ModelsConfig(
            plan: .sonnet, implement: .opus, review: .haiku
        )
        let plan = model.addWorkflowTab(action: .plan, slug: "x")
        let impl = model.addWorkflowTab(action: .implement, slug: "x")
        let rev = model.addWorkflowTab(action: .review, slug: "x")
        #expect(plan.session.modelChoice == .sonnet)
        #expect(impl.session.modelChoice == .opus)
        #expect(rev.session.modelChoice == .haiku)
    }

    @Test("missing modelsConfig falls back to slot defaults")
    func defaultModelFallback() {
        let model = makeModel()
        model.modelsConfig = nil
        model.addTab()
        let wf = model.addWorkflowTab(action: .implement, slug: "x")
        #expect(model.tabs.last?.session.modelChoice == ModelsConfig.terminalsDefault)
        #expect(wf.session.modelChoice == ModelsConfig.implementDefault)
    }

    // MARK: - Helpers

    private func makeModel(
        excludedSessionIDs: @escaping @MainActor () -> Set<String> = { [] }
    ) -> TerminalTabsModel {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTabsModelTests-\(UUID().uuidString)")
        let binary = URL(filePath: "/usr/bin/true")
        let session = TerminalClaudeSession(
            cwd: cwd,
            binaryURL: binary,
            excludedSessionIDs: excludedSessionIDs,
            persistConversationID: false
        )
        return TerminalTabsModel(
            cwd: cwd,
            binaryURL: binary,
            initialSession: session,
            excludedSessionIDs: excludedSessionIDs
        )
    }

    private func isStarting(_ state: TerminalClaudeSession.State) -> Bool {
        if case .starting = state { return true }
        return false
    }

    private func isExited(_ state: TerminalClaudeSession.State) -> Bool {
        if case .exited = state { return true }
        return false
    }

    private func isIdle(_ state: TerminalClaudeSession.State) -> Bool {
        if case .idle = state { return true }
        return false
    }
}
