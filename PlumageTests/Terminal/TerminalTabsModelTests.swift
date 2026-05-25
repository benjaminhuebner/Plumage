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
        #expect(model.tabs[0].title == "Terminal 1")
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
        #expect(model.tabs.map(\.title) == ["Terminal 1", "Terminal 2", "Terminal 3"])

        let middleID = model.tabs[1].id
        model.closeTab(id: middleID)

        #expect(model.tabs.count == 2)
        #expect(model.tabs.map(\.title) == ["Terminal 1", "Terminal 2"])
    }

    @Test("closeTab on the only tab is a no-op")
    func closeLastTabIsNoOp() {
        let model = makeModel()
        let onlyID = model.tabs[0].id
        #expect(model.canCloseActiveTab == false)

        model.closeTab(id: onlyID)

        #expect(model.tabs.count == 1)
        #expect(model.tabs[0].id == onlyID)
    }

    @Test("closing the active tab selects the left neighbor")
    func closingActivePicksLeftNeighbor() {
        let model = makeModel()
        model.addTab()
        model.addTab()
        let firstID = model.tabs[0].id
        let middleID = model.tabs[1].id
        let lastID = model.tabs[2].id

        // Active = last (set by addTab). Closing it picks the new last (was middle).
        model.closeTab(id: lastID)
        #expect(model.selectedTabID == middleID)

        // Now active = middle. Close it; left neighbor = first.
        model.closeTab(id: middleID)
        #expect(model.selectedTabID == firstID)
    }

    @Test("closing the leftmost active tab falls back to the right neighbor")
    func closingLeftmostFallsRight() {
        let model = makeModel()
        model.addTab()
        let firstID = model.tabs[0].id
        let secondID = model.tabs[1].id

        model.selectTab(at: 0)
        #expect(model.selectedTabID == firstID)

        model.closeTab(id: firstID)
        #expect(model.tabs.count == 1)
        #expect(model.selectedTabID == secondID)
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
