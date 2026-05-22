import SwiftUI

struct ProjectWindow: View {
    let handle: ProjectHandle

    @State private var model = ProjectModel()
    @State private var kanban = ProjectKanbanModel()
    @State private var navigator = NavigatorModel()
    @State private var selectedRoute: NavigatorRoute = .kanban
    @SceneStorage("nav.selection") private var persistedRouteData: String = ""
    @State private var detailOriginRoute: NavigatorRoute?
    @State private var showCreateSheet = false
    @State private var createInitialStatus: IssueStatus = .draft
    @State private var indicator = StatusIndicatorModel()
    @State private var claudeUsage = ClaudeUsageModel()
    @State private var claudeStatus = ClaudeStatusModel()
    @State private var usageClient = ClaudeUsageClient()
    @State private var statusClient = ClaudeStatusPageClient()
    @State private var session: ClaudeSession
    @State private var terminalSession: TerminalClaudeSession
    @State private var xcodeRun: XcodeRunModel
    @State private var xcodeRunController: XcodeRunController
    @State private var showBuildLog = false
    @SceneStorage("claudeDock.open") private var isDockOpen = false
    @SceneStorage("inspector.terminal.open") private var isTerminalInspectorOpen = false
    @SceneStorage("xcode.scheme") private var persistedScheme: String = ""
    @SceneStorage("xcode.destination") private var persistedDestinationID: String = ""
    // Cached focused-scene action. Computing `isLoaded ? { … } : nil` inline
    // produces a new closure per body re-eval, which the focus system
    // republishes; under fast state churn (kanban refresh, indicator detect)
    // it warns "FocusedValue update tried to update multiple times per
    // frame". State-cached + onChange keeps the published identity stable.
    @State private var createIssueAction: EditorAction?
    @State private var beginInlineCreateAction: InlineCreateInvoker?

    @Environment(\.processRunner) private var processRunner
    @Environment(\.scenePhase) private var scenePhase
    @FocusedValue(\.issueDetailBackToBoard) private var backToBoardAction: EditorAction?

    init(handle: ProjectHandle) {
        self.handle = handle
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        self._session = State(
            initialValue: ClaudeSession(cwd: handle.url, binaryURL: binary)
        )
        self._terminalSession = State(
            initialValue: TerminalClaudeSession(cwd: handle.url, binaryURL: binary)
        )
        let runModel = XcodeRunModel()
        self._xcodeRun = State(initialValue: runModel)
        self._xcodeRunController = State(initialValue: XcodeRunController(model: runModel))
    }

    var body: some View {
        baseStack
            .environment(kanban)
            .environment(navigator)
            .environment(\.openCreateIssue) { status in
                createInitialStatus = status
                showCreateSheet = true
            }
            .frame(minWidth: 600, minHeight: 400)
            .background(WindowFrameAutosaver(autosaveName: "plumage.project.window"))
            .navigationTitle(displayTitle)
            .focusedSceneValue(\.createIssueInDefaultColumn, createIssueAction)
            .focusedSceneValue(\.beginInlineCreate, beginInlineCreateAction)
            .focusedSceneValue(\.terminalToggle, $isTerminalInspectorOpen)
            .focusedSceneValue(\.chatDockToggle, $isDockOpen)
            .task(id: handle.url) {
                if let restored = NavigatorRoute(persistedString: persistedRouteData) {
                    selectedRoute = restored
                }
                // @State ignores re-assignment from init, so a window reused
                // for a different handle keeps the stale session.cwd unless
                // we rebuild here. attach() then handles the
                // start/restart/no-op decision.
                session = ClaudeSession.rebuilt(for: handle.url, replacing: session)
                terminalSession = TerminalClaudeSession.rebuilt(
                    for: handle.url, replacing: terminalSession)
                session.attach()
                terminalSession.attach()
                async let reload: Void = model.reload(at: handle.url)
                async let run: Void = kanban.run(projectURL: handle.url)
                async let detect: Void = indicator.detect(using: processRunner)
                async let navLoad: Void = navigator.reload(projectURL: handle.url)
                async let xcodeDiscover: Void = xcodeRun.discover(projectURL: handle.url)
                async let usagePoll: Void = pollClaudeUsage()
                async let statusPoll: Void = pollClaudeStatus()
                _ = await (reload, run, detect, navLoad, xcodeDiscover, usagePoll, statusPoll)
                refreshCreateIssueAction()
            }
            .onChange(of: isLoaded) { _, _ in refreshCreateIssueAction() }
            .onChange(of: xcodeRun.discoveryState) { _, state in
                if state == .ready {
                    Task {
                        await xcodeRun.restoreSelections(
                            scheme: persistedScheme.isEmpty ? nil : persistedScheme,
                            destinationID: persistedDestinationID.isEmpty ? nil : persistedDestinationID
                        )
                    }
                }
            }
            .onChange(of: xcodeRun.selectedScheme) { _, scheme in
                persistedScheme = scheme ?? ""
            }
            .onChange(of: xcodeRun.selectedDestination) { _, destination in
                persistedDestinationID = destination?.id ?? ""
            }
            .onDisappear {
                session.stop()
                terminalSession.stop()
                xcodeRunController.cancelRun()
            }
            .onChange(of: selectedRoute) { _, new in
                persistedRouteData = new.persistedString
                if case .issue = new {
                } else {
                    detailOriginRoute = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await navigator.reload(projectURL: handle.url) }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                NavigationStack {
                    IssueDetailView(projectURL: handle.url, initialStatus: createInitialStatus)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showCreateSheet = false }
                            }
                        }
                }
                // Sheets present in their own SwiftUI tree and don't inherit
                // the presenter's environment. IssueDetailView's
                // @Environment(ProjectKanbanModel.self) crashes without these.
                .environment(kanban)
                .environment(navigator)
                .frame(minWidth: 720, minHeight: 600)
            }
    }

    @ViewBuilder
    private var baseStack: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 80, ideal: 700, max: .infinity)
                .inspector(isPresented: $isTerminalInspectorOpen) {
                    TerminalInspectorView(session: terminalSession)
                        .inspectorColumnWidth(min: 320, ideal: 480, max: 600)
                }
        }
        .toolbar {
            if let backToBoardAction {
                ToolbarItem(placement: .navigation) {
                    Button("Board", systemImage: "chevron.backward") {
                        backToBoardAction.run()
                    }
                    .help("Back to kanban board")
                }
            }
            XcodeToolbarItems(
                model: xcodeRun,
                onRun: { xcodeRunController.startRun() },
                onCancel: { xcodeRunController.cancelRun() },
                onReload: {
                    Task { await xcodeRun.reload(projectURL: handle.url) }
                },
                onInstallXcode: {
                    if let url = xcodeRun.installXcodeURL {
                        NSWorkspace.shared.open(url)
                    }
                },
                showLog: $showBuildLog
            )
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isTerminalInspectorOpen.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Terminal Inspector (⌥⌘T)")
                .accessibilityLabel("Terminal Inspector")
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        NavigatorSidebar(selection: $selectedRoute, projectURL: handle.url)
            .navigationSplitViewColumnWidth(240)
    }

    @ViewBuilder
    private var detail: some View {
        detailContent
            .overlay(alignment: .bottomTrailing) {
                ClaudeDockOverlay(
                    session: session,
                    indicatorState: indicator.state,
                    isOpen: $isDockOpen
                )
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let config):
            VStack(alignment: .leading, spacing: 0) {
                NavigatorDetail(
                    route: selectedRoute,
                    projectURL: handle.url,
                    padding: config.issueIdPadding ?? 5
                )
                // .id(route) forces SwiftUI to tear down + rebuild the detail
                // subtree on every route change. Without this, DocEditorView
                // and IssueDetailView hold @State models that were initialized
                // with the *first* file/issue URL — Swift View identity is
                // position-based, so the same struct slot re-uses the same
                // @State on every re-render. New URL into init() is ignored
                // and .task(id:) never fires because model.fileURL never
                // changes. See axiom-swiftui debugging.md Root Cause 5.
                .id(selectedRoute)
                .environment(\.kanbanHighlightedID, kanban.highlightedIssueID)
                .environment(\.openSpec) { route in
                    if selectedRoute == .kanban, case .issue = route {
                        detailOriginRoute = .kanban
                    }
                    selectedRoute = route
                }
                .environment(\.openCreateIssue) { status in
                    createInitialStatus = status
                    showCreateSheet = true
                }
                .environment(\.dismissToOrigin, backToOriginAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                ProjectStatusBar(
                    indicatorState: indicator.state,
                    usageModel: claudeUsage,
                    statusModel: claudeStatus,
                    banner: navigator.dropRejectMessage
                )
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't open this project.")
                    .font(.headline)
                Text(Self.message(for: error))
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var displayTitle: String {
        if case .loaded(let config) = model.state { return config.name }
        return handle.url.lastPathComponent
    }

    private var backToOriginAction: (() -> Void)? {
        guard let origin = detailOriginRoute, origin == .kanban else { return nil }
        return { selectedRoute = .kanban }
    }

    private var isLoaded: Bool {
        if case .loaded = model.state { return true }
        return false
    }

    // Polling cadence: 90s for usage (spec'd) and 60s for status. Both loops
    // exit via Task cancellation when .task(id:) re-fires or onDisappear stops
    // the parent; Task.sleep is the natural cancellation point.
    private func pollClaudeUsage() async {
        await claudeUsage.refresh(using: usageClient)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(90))
            } catch {
                return
            }
            await claudeUsage.refresh(using: usageClient)
        }
    }

    private func pollClaudeStatus() async {
        await claudeStatus.refresh(using: statusClient)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            await claudeStatus.refresh(using: statusClient)
        }
    }

    private func refreshCreateIssueAction() {
        if isLoaded {
            if createIssueAction == nil {
                createIssueAction = EditorAction {
                    createInitialStatus = .draft
                    showCreateSheet = true
                }
            }
            if beginInlineCreateAction == nil {
                beginInlineCreateAction = InlineCreateInvoker { section in
                    navigator.beginPendingCreate(section)
                }
            }
        } else {
            if createIssueAction != nil { createIssueAction = nil }
            if beginInlineCreateAction != nil { beginInlineCreateAction = nil }
        }
    }

    static func message(for error: ConfigLoader.LoadError) -> String {
        switch error {
        case .noBundle(let folder):
            return "No Plumage bundle at \(folder.path)."
        case .noConfigFile(let bundle):
            return "Plumage bundle at \(bundle.path) has no config.json."
        case .multipleBundles(let urls):
            let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
            return "Multiple Plumage bundles found: \(names). Expected exactly one."
        case .schemaTooNew(let version, let supportedUpTo):
            return
                "This project needs a newer Plumage (config schemaVersion \(version), this build supports up to \(supportedUpTo))."
        case .invalidJSON(let message):
            return "This Plumage config is invalid: \(message)"
        }
    }
}

#Preview {
    ProjectWindow(handle: ProjectHandle(url: previewProjectURL()))
}

@MainActor
private func previewProjectURL() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlumagePreview-\(UUID().uuidString)")
    let bundle = dir.appendingPathComponent("Preview.plumage")
    try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    let config = """
        {
          "name": "Plumage",
          "schemaVersion": 2,
          "issueIdPadding": 5
        }
        """
    try? config.write(
        to: bundle.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    return dir
}
