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
    func matchingTemplateCreatesTab() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
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
        await launcher.workflowTask?.value

        #expect(tabs.tabs.count == 2)
        #expect(tabs.tabs.last?.isWorkflow == true)
        #expect(banners.isEmpty)
        launcher.cancel()
        tabs.stopAll()
    }

    // Launcher whose detection seams report an idle checkout (no git, no
    // file system involved).
    private func makeIdleLauncher() -> WorkflowLauncher {
        let launcher = WorkflowLauncher()
        launcher.listWorktreeRoots = { [$0] }
        launcher.scanLiveRuns = { _ in [] }
        launcher.scanQueuedRuns = { _ in [] }
        launcher.runStateExists = { _, _ in false }
        return launcher
    }

    private func runImplement(
        _ launcher: WorkflowLauncher,
        slug: String,
        tabs: TerminalTabsModel,
        onBanner: @escaping @MainActor (String) -> Void = { _ in }
    ) async {
        launcher.run(
            action: .implement,
            folderName: slug,
            issueType: .chore,
            projectURL: FileManager.default.temporaryDirectory,
            override: WorkflowOverride(command: "#if chore\n/chore-only\n#end"),
            tabs: tabs,
            openInspector: {},
            showBanner: onBanner
        )
        await launcher.workflowTask?.value
    }

    private func runImplement(
        _ launcher: WorkflowLauncher,
        tabs: TerminalTabsModel,
        banners: inout [String]
    ) async {
        var sink: [String] = []
        launcher.run(
            action: .implement,
            folderName: "00001-test",
            issueType: .chore,
            projectURL: FileManager.default.temporaryDirectory,
            override: WorkflowOverride(command: "#if chore\n/chore-only\n#end"),
            tabs: tabs,
            openInspector: {},
            showBanner: { sink.append($0) }
        )
        await launcher.workflowTask?.value
        banners = sink
    }

    @Test("an issue that is live in any worktree is refused")
    func sameIssueLiveAnywhereIsRefused() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanLiveRuns = { roots in
            [
                WorktreeImplementRun(
                    checkoutRoot: roots[0].appending(component: "Proj-00001-test"),
                    run: LiveImplementRun(issue: "00001-test", agentPid: 1)
                )
            ]
        }
        var banners: [String] = []

        await runImplement(launcher, tabs: tabs, banners: &banners)

        #expect(tabs.tabs.count == 1)
        #expect(banners.first?.contains("already being implemented") == true)
        tabs.stopAll()
    }

    @Test("an issue that is already queued is refused")
    func sameIssueQueuedIsRefused() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanQueuedRuns = { _ in
            [QueuedImplementRun(issue: "00001-test")]
        }
        var banners: [String] = []

        await runImplement(launcher, tabs: tabs, banners: &banners)

        #expect(tabs.tabs.count == 1)
        #expect(banners.first?.contains("already waiting") == true)
        tabs.stopAll()
    }

    @Test("an issue queued in another worktree is refused")
    func sameIssueQueuedInOtherWorktreeIsRefused() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.listWorktreeRoots = {
            [$0, $0.appending(component: "Proj-wt", directoryHint: .isDirectory)]
        }
        launcher.scanQueuedRuns = { root in
            root.lastPathComponent == "Proj-wt"
                ? [QueuedImplementRun(issue: "00001-test")] : []
        }
        var banners: [String] = []

        await runImplement(launcher, tabs: tabs, banners: &banners)

        #expect(tabs.tabs.count == 1)
        #expect(banners.first?.contains("already waiting") == true)
        #expect(launcher.pendingImplement == nil)
        tabs.stopAll()
    }

    @Test("a queue entry in another worktree does not mark the primary checkout busy")
    func otherWorktreeQueueDoesNotBlockPrimary() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.listWorktreeRoots = {
            [$0, $0.appending(component: "Proj-wt", directoryHint: .isDirectory)]
        }
        launcher.scanQueuedRuns = { root in
            root.lastPathComponent == "Proj-wt"
                ? [QueuedImplementRun(issue: "00099-other")] : []
        }
        var banners: [String] = []

        await runImplement(launcher, tabs: tabs, banners: &banners)

        #expect(tabs.tabs.count == 2)
        #expect(launcher.pendingImplement == nil)
        #expect(banners.isEmpty)
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("busy primary checkout asks instead of starting")
    func busyPrimaryAsks() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanLiveRuns = { roots in
            [
                WorktreeImplementRun(
                    checkoutRoot: roots[0],
                    run: LiveImplementRun(issue: "00099-other", agentPid: 1)
                )
            ]
        }
        var banners: [String] = []

        await runImplement(launcher, tabs: tabs, banners: &banners)

        #expect(tabs.tabs.count == 1)
        #expect(banners.isEmpty)
        #expect(launcher.pendingImplement?.blocker == "00099-other")
        #expect(launcher.pendingImplement?.slug == "00001-test")
        tabs.stopAll()
    }

    @Test("wait choice opens a normal tab whose title has no worktree suffix")
    func waitChoiceOpensNormalTab() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanQueuedRuns = { _ in
            [QueuedImplementRun(issue: "00099-other")]
        }
        var banners: [String] = []
        await runImplement(launcher, tabs: tabs, banners: &banners)
        #expect(launcher.pendingImplement != nil)

        // confirm(.wait) opens the tab synchronously; awaiting workflowTask
        // here would await the in-flight inject and its 5 s ready-timeout.
        launcher.confirmPendingImplement(.wait)

        #expect(tabs.tabs.count == 2)
        #expect(tabs.tabs.last?.title == WorkflowAction.implement.tabTitle(slug: "00001-test"))
        #expect(launcher.pendingImplement == nil)
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("worktree choice provisions, banners the path, and suffixes the tab title")
    func worktreeChoiceProvisionsAndOpensWorktreeTab() async throws {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanLiveRuns = { roots in
            [
                WorktreeImplementRun(
                    checkoutRoot: roots[0],
                    run: LiveImplementRun(issue: "00099-other", agentPid: 1)
                )
            ]
        }
        let worktree = FileManager.default.temporaryDirectory
            .appending(component: "Proj-00001-test", directoryHint: .isDirectory)
        launcher.provisionWorktree = { _, _ in
            WorktreeProvisionResult(worktreeRoot: worktree, reusedExisting: false)
        }
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
        await launcher.workflowTask?.value
        #expect(launcher.pendingImplement != nil)

        launcher.confirmPendingImplement(.worktree)
        await launcher.workflowTask?.value

        #expect(banners.first?.contains(worktree.path) == true)
        #expect(tabs.tabs.count == 2)
        let title = try #require(tabs.tabs.last?.title)
        #expect(
            title
                == TerminalTabsModel.worktreeTitle(
                    base: WorkflowAction.implement.tabTitle(slug: "00001-test")))
        #expect(
            tabs.findWorkflowTab(action: .implement, slug: "00001-test")?.id
                == tabs.tabs.last?.id)
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("provisioning failure keeps a persistent error and opens no tab")
    func provisionFailureKeepsError() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanQueuedRuns = { _ in
            [QueuedImplementRun(issue: "00099-other")]
        }
        launcher.provisionWorktree = { _, _ in
            throw WorktreeProvisionError.scriptFailed(message: "error: target path already exists")
        }
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
        await launcher.workflowTask?.value
        launcher.confirmPendingImplement(.worktree)
        await launcher.workflowTask?.value

        #expect(launcher.worktreeProvisionError?.contains("target path already exists") == true)
        #expect(banners.isEmpty)
        #expect(tabs.tabs.count == 1)
        tabs.stopAll()
    }

    @Test("retry after a provisioning failure re-runs the kept request")
    func provisionRetryReRunsRequest() async throws {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        launcher.scanQueuedRuns = { _ in
            [QueuedImplementRun(issue: "00099-other")]
        }
        launcher.provisionWorktree = { _, _ in
            throw WorktreeProvisionError.scriptFailed(message: "transient failure")
        }
        var banners: [String] = []
        await runImplement(launcher, tabs: tabs, banners: &banners)
        launcher.confirmPendingImplement(.worktree)
        await launcher.workflowTask?.value
        #expect(launcher.worktreeProvisionError != nil)

        let worktree = FileManager.default.temporaryDirectory
            .appending(component: "Proj-00001-test", directoryHint: .isDirectory)
        launcher.provisionWorktree = { _, _ in
            WorktreeProvisionResult(worktreeRoot: worktree, reusedExisting: false)
        }
        launcher.retryWorktreeProvision()
        await launcher.workflowTask?.value

        #expect(launcher.worktreeProvisionError == nil)
        #expect(tabs.tabs.count == 2)
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("a second implement during the first one's startup window asks")
    func secondImplementDuringStartupWindowAsks() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        await runImplement(launcher, slug: "00001-test", tabs: tabs)
        #expect(tabs.tabs.count == 2)
        #expect(launcher.pendingImplement == nil)

        // No run-state, no queue entry yet — exactly the user's two quick
        // clicks. The open implement tab itself must count as busy.
        await runImplement(launcher, slug: "00002-other", tabs: tabs)

        #expect(tabs.tabs.count == 2)
        #expect(launcher.pendingImplement?.blocker == "00001-test")
        #expect(launcher.pendingImplement?.slug == "00002-other")
        launcher.cancelPendingImplement()
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("the startup marker clears once the run-state exists")
    func startupMarkerClearsWhenRunStateAppears() async {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        await runImplement(launcher, slug: "00001-test", tabs: tabs)

        // The first run wrote its run-state (here: a dead/crashed one, so the
        // live scan stays empty) — the marker must defer to the file scan.
        launcher.runStateExists = { _, slug in slug == "00001-test" }
        await runImplement(launcher, slug: "00002-other", tabs: tabs)

        #expect(launcher.pendingImplement == nil)
        #expect(tabs.tabs.count == 3)
        launcher.cancel()
        tabs.stopAll()
    }

    @Test("the startup marker clears when its tab is closed")
    func startupMarkerClearsWhenTabCloses() async throws {
        let tabs = makeTabs()
        let launcher = makeIdleLauncher()
        await runImplement(launcher, slug: "00001-test", tabs: tabs)
        let firstTab = try #require(tabs.tabs.last)
        tabs.closeTab(id: firstTab.id)
        #expect(tabs.tabs.count == 1)

        await runImplement(launcher, slug: "00002-other", tabs: tabs)

        #expect(launcher.pendingImplement == nil)
        #expect(tabs.tabs.count == 2)
        launcher.cancel()
        tabs.stopAll()
    }
}
