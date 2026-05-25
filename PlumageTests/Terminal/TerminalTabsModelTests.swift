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
        // Mirror ProjectWindow's flow: caller attaches the initial session;
        // addTab() attaches new ones internally.
        model.activeSession?.attach()
        model.addTab()
        model.addTab()
        for tab in model.tabs {
            #expect(isStarting(tab.session.state))
        }

        model.stopAll()

        for tab in model.tabs {
            #expect(isExited(tab.session.state))
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

    // MARK: - Helpers

    private func makeModel() -> TerminalTabsModel {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalTabsModelTests-\(UUID().uuidString)")
        let binary = URL(filePath: "/usr/bin/true")
        let session = TerminalClaudeSession(
            cwd: cwd, binaryURL: binary, persistConversationID: false
        )
        return TerminalTabsModel(
            cwd: cwd, binaryURL: binary, initialSession: session
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
}
