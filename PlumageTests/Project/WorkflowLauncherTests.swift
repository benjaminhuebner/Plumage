import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("WorkflowLauncher")
struct WorkflowLauncherTests {
    private func makeTabs() -> TerminalTabsModel {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkflowLauncherTests-\(UUID().uuidString)")
        let binary = URL(filePath: "/usr/bin/true")
        let session = TerminalClaudeSession(
            cwd: cwd,
            binaryURL: binary,
            persistConversationID: false
        )
        return TerminalTabsModel(cwd: cwd, binaryURL: binary, initialSession: session)
    }

    @Test("empty per-type template shows a banner and creates no tab")
    func emptyTemplateStopsRun() {
        let tabs = makeTabs()
        let launcher = WorkflowLauncher()
        var banners: [String] = []
        var inspectorOpened = false

        launcher.run(
            action: .implement,
            folderName: "00001-test",
            issueType: .feature,
            projectURL: FileManager.default.temporaryDirectory,
            override: WorkflowOverride(command: "#if chore\n/chore-only\n#end"),
            tabs: tabs,
            openInspector: { inspectorOpened = true },
            showBanner: { banners.append($0) }
        )

        #expect(tabs.tabs.count == 1)
        #expect(banners.count == 1)
        #expect(banners.first?.contains("no command for this issue type") == true)
        #expect(!inspectorOpened)
    }

    @Test("matching per-type template creates the workflow tab")
    func matchingTemplateCreatesTab() {
        let tabs = makeTabs()
        let launcher = WorkflowLauncher()
        var banners: [String] = []

        launcher.run(
            action: .implement,
            folderName: "00001-test",
            issueType: .chore,
            projectURL: FileManager.default.temporaryDirectory,
            override: WorkflowOverride(command: "#if chore\n/chore-only\n#end"),
            tabs: tabs,
            openInspector: {},
            showBanner: { banners.append($0) }
        )

        #expect(tabs.tabs.count == 2)
        #expect(tabs.tabs.last?.isWorkflow == true)
        #expect(banners.isEmpty)
        launcher.cancel()
        tabs.stopAll()
    }
}
