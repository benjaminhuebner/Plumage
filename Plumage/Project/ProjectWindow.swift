import SwiftUI
import os

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
    @State private var showCommitSheet = false
    @State private var showSyncSheet = false
    @State private var syncOperation: GitSyncOperation = .push
    @State private var commitAction: EditorAction?
    @State private var pushAction: EditorAction?
    @State private var pullAction: EditorAction?
    @State private var indicator = StatusIndicatorModel()
    @State private var claudeUsage = ClaudeUsageModel()
    @State private var claudeStatus = ClaudeStatusModel()
    @State private var gitModel = ProjectGitModel()
    @State private var usageClient = ClaudeUsageClient()
    @State private var statusClient = ClaudeStatusPageClient()
    @State private var session: ClaudeSession
    @State private var terminalTabs: TerminalTabsModel
    @State private var xcodeRun: XcodeRunModel
    @State private var xcodeRunController: XcodeRunController
    @State private var showBuildLog = false
    @SceneStorage("claudeDock.open") private var isDockOpen = false
    @SceneStorage("inspector.terminal.open") private var isTerminalInspectorOpen = false
    // Pre-#00032 the dock panel hosted a Chat/Terminal mode switcher whose
    // selection persisted under "terminalPaneMode". This branch moved the
    // terminal out into an inspector with its own storage key; the one-shot
    // migration below maps a legacy "terminal" selection forward so users
    // who left the dock in terminal mode see the inspector open on first
    // launch instead of nothing.
    @SceneStorage("terminalPaneMode") private var legacyTerminalPaneMode: String = ""
    @SceneStorage("inspector.terminal.migrated") private var hasMigratedLegacyPaneMode = false
    @SceneStorage("xcode.scheme") private var persistedScheme: String = ""
    @SceneStorage("xcode.destination") private var persistedDestinationID: String = ""
    // Cached focused-scene action. Computing `isLoaded ? { … } : nil` inline
    // produces a new closure per body re-eval, which the focus system
    // republishes; under fast state churn (kanban refresh, indicator detect)
    // it warns "FocusedValue update tried to update multiple times per
    // frame". State-cached + onChange keeps the published identity stable.
    @State private var createIssueAction: EditorAction?
    @State private var beginInlineCreateAction: InlineCreateInvoker?
    // Single in-flight workflow inject. Replacing it cancels the prior task
    // so a quick second button-press doesn't leave the prior task's body
    // enqueue stranded — see #00034 race fix.
    @State private var workflowTask: Task<Void, Never>?

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
        // Every terminal tab — including the main one at index 0 — runs as
        // an ephemeral session: fresh conversationID per window-open, no
        // disk persistence, no reconcile pickup. A persistent main tab
        // would adopt sibling claude runs that wrote the same log dir
        // last (a /plan or /implement subprocess, but also any external
        // `claude` invocation in macOS-Terminal). The sibling-exclude
        // plumbing inside TerminalTabsModel can only filter Plumage's own
        // tabs, not arbitrary external callers — so the safer choice is
        // to never persist or reconcile at all. Trade-off: window-reopen
        // drops the user's terminal history. Accepted (2026-05-25, #00037
        // post-review).
        let initialTerminalSession = TerminalClaudeSession(
            cwd: handle.url, binaryURL: binary, persistConversationID: false
        )
        self._terminalTabs = State(
            initialValue: TerminalTabsModel(
                cwd: handle.url,
                binaryURL: binary,
                initialSession: initialTerminalSession
            )
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
            // minHeight=620: dock panel is 560pt + 16pt bottom padding + ~28pt
            // titlebar = 604pt minimum vertical room; round up for safe-area
            // margin. Lower values clip the panel's close button behind the
            // titlebar.
            .frame(minWidth: 1100, minHeight: 620)
            .background(WindowFrameAutosaver(autosaveName: "plumage.project.window"))
            .navigationTitle(displayTitle)
            .focusedSceneValue(\.createIssueInDefaultColumn, createIssueAction)
            .focusedSceneValue(\.beginInlineCreate, beginInlineCreateAction)
            .focusedSceneValue(\.terminalToggle, $isTerminalInspectorOpen)
            .focusedSceneValue(\.chatDockToggle, $isDockOpen)
            .focusedSceneValue(\.gitCommitAction, commitAction)
            .focusedSceneValue(\.gitPushAction, pushAction)
            .focusedSceneValue(\.gitPullAction, pullAction)
            .task(id: handle.url) {
                if !hasMigratedLegacyPaneMode {
                    if legacyTerminalPaneMode == "terminal" {
                        isTerminalInspectorOpen = true
                    }
                    legacyTerminalPaneMode = ""
                    hasMigratedLegacyPaneMode = true
                }
                if let restored = NavigatorRoute(persistedString: persistedRouteData) {
                    selectedRoute = restored
                }
                // @State ignores re-assignment from init, so a window reused
                // for a different handle keeps the stale session.cwd unless
                // we rebuild here. attach() then handles the
                // start/restart/no-op decision.
                //
                // Order matters: rebuilt() must run BEFORE setExcludedSessionIDs
                // below — the closure captures `session` weakly at construction
                // time, so it must close over the post-rebuilt instance. If
                // setExcludedSessionIDs ran first, it would close over the
                // about-to-be-released old session, return [] once rebuilt
                // swapped it out, and silently allow the chat session's ID to
                // be adopted by the terminal reconcile.
                // Load config synchronously so the initial sessions pick up
                // per-project model overrides before attach(). The async
                // model.reload below covers the @Observable view-state path.
                let initialConfig = try? ConfigLoader.load(at: handle.url)
                let chatModel =
                    initialConfig?.models?.chat ?? ModelsConfig.chatDefault
                let terminalsModel =
                    initialConfig?.models?.terminals ?? ModelsConfig.terminalsDefault
                session = ClaudeSession.rebuilt(
                    for: handle.url, replacing: session, modelChoice: chatModel
                )
                // Window reused for a different handle, OR the terminals
                // model preference changed in config: rebuild the tabs model
                // so the next-spawned default tab uses the right model.
                if terminalTabs.cwd != handle.url
                    || terminalTabs.mainSession.modelChoice != terminalsModel
                {
                    terminalTabs.stopAll()
                    let newBinary =
                        (try? ProductionProcessRunner.locateBinary())
                        ?? URL(filePath: "/dev/null")
                    let newInitial = TerminalClaudeSession(
                        cwd: handle.url, binaryURL: newBinary,
                        modelChoice: terminalsModel,
                        persistConversationID: false
                    )
                    terminalTabs = TerminalTabsModel(
                        cwd: handle.url,
                        binaryURL: newBinary,
                        initialSession: newInitial,
                        modelsConfig: initialConfig?.models
                    )
                } else {
                    terminalTabs.modelsConfig = initialConfig?.models
                }
                // Chat shares the claude log dir with terminal; without this
                // exclude the terminal's reconcile would adopt chat's session
                // ID if chat happened to be the last writer. Per-tab smart
                // closures in TerminalTabsModel read this lazily, so updating
                // the shared provider is enough — no per-tab fan-out needed.
                terminalTabs.setSharedExcludedSessionIDs { [weak session] in
                    guard let id = session?.conversationID else { return [] }
                    return [id]
                }
                // Closing a workflow tab mid-inject must cancel the inject
                // task — otherwise it strands for up to ~850ms inside its
                // bodyDelay sleep, holding the dead session alive. Only one
                // workflowTask is ever in flight at a time, so any
                // workflow-tab close that races inject() is the right cancel.
                terminalTabs.onTabClosed = { closed in
                    if closed.isWorkflow {
                        workflowTask?.cancel()
                    }
                }
                session.attach()
                // Terminal sessions don't get explicit attach() here —
                // SwiftTermBridge.makeNSView attaches each tab when its
                // EmbeddedTerminalView mounts, which is what survives
                // scene-phase recovery without leaving non-active tabs
                // stranded in .exited.
                gitModel.start(repoURL: handle.url)
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
            .onChange(of: isLoaded) { _, _ in refreshGitActions() }
            .onChange(of: gitModel.repoState.isGitRepo) { _, _ in refreshGitActions() }
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
                terminalTabs.stopAll()
                workflowTask?.cancel()
                xcodeRunController.cancelRun()
                gitModel.stop()
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
                .environment(\.onIssueCreated) { folderName in
                    showCreateSheet = false
                    selectedRoute = .issue(folderName: folderName)
                }
                .frame(minWidth: 720, minHeight: 600)
            }
            .sheet(isPresented: $showCommitSheet) {
                GitCommitView(
                    model: GitCommitModel(
                        repoURL: handle.url,
                        watcher: GitRepoWatcher(repoURL: handle.url)
                    ),
                    onDismiss: { showCommitSheet = false }
                )
            }
            .sheet(isPresented: $showSyncSheet) {
                GitSyncView(
                    model: GitSyncModel(
                        repoURL: handle.url,
                        operation: syncOperation,
                        currentBranch: gitModel.repoState.branchName
                    ),
                    onDismiss: { showSyncSheet = false }
                )
            }
    }

    @ViewBuilder
    private var baseStack: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Dock overlay sits at the detail column's bottom-trailing
                // so it shifts left when the inspector opens.
                .overlay(alignment: .bottomTrailing) {
                    ClaudeDockOverlay(
                        session: session,
                        indicatorState: indicator.state,
                        isOpen: $isDockOpen
                    )
                }
                .navigationSplitViewColumnWidth(min: 50, ideal: 700, max: .infinity)
                .inspector(isPresented: $isTerminalInspectorOpen) {
                    TerminalInspectorView(tabsModel: terminalTabs)
                        .inspectorColumnWidth(min: 400, ideal: 480, max: 560)
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
                        .foregroundStyle(
                            isTerminalInspectorOpen ? Color.accentColor : Color.primary
                        )
                }
                .help("Terminal Inspector (⌥⌘T)")
                .accessibilityLabel("Terminal Inspector")
                .accessibilityValue(isTerminalInspectorOpen ? "Sichtbar" : "Ausgeblendet")
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
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
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
                .environment(\.runWorkflow, runWorkflow(_:folderName:))
                .environment(\.onProjectConfigSaved) { saved in
                    // Mirror the disk-write into ProjectModel so the rest of
                    // the window (runWorkflow → currentConfig().workflows)
                    // and the live tabs model both see the picker change
                    // immediately, without waiting for a window reopen.
                    model.setLoaded(saved)
                    terminalTabs.modelsConfig = saved.models
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // .clipped() applies ONLY to NavigatorDetail so editor views
                // that don't wrap horizontally stay contained within the
                // detail column. ProjectStatusBar sits below the clip and
                // remains visible even when detail is narrow (inspector open
                // at max width + sidebar fixed at 240 leaves ~300pt — small
                // enough that .fixedSize() chips on the status bar would
                // otherwise be cut off without a hint).
                .clipped()
                ProjectStatusBar(
                    indicatorState: indicator.state,
                    usageModel: claudeUsage,
                    statusModel: claudeStatus,
                    repoState: gitModel.repoState,
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

    private func runWorkflow(_ action: WorkflowAction, folderName: String) {
        // Reject folder names that would corrupt the inject: \r submits in
        // claude's REPL, \n splits, \0 is undefined. isShellSafe checks
        // exactly these three. Folder names are user-controlled via Finder
        // rename, so this is a real attack surface, not just defense in depth.
        guard TerminalClaudeSession.isShellSafe(folderName) else {
            Self.log.warning(
                "runWorkflow: refusing inject for \(action.slug, privacy: .public) — folderName contains control chars."
            )
            return
        }

        // Cancel any prior inject still mid-sleep before its next enqueue.
        workflowTask?.cancel()
        isTerminalInspectorOpen = true

        // Find-or-create a per-workflow tab so each Plan/Implement/Review
        // gets its own claude subprocess with the right --permission-mode and
        // leaves the main terminal free. Title match is exact ("<Action>:
        // <slug>"); a repeat click on the same action+issue selects the
        // existing tab without a second inject.
        if let existing = terminalTabs.findWorkflowTab(action: action, slug: folderName) {
            terminalTabs.selectedTabID = existing.id
            return
        }
        let workflowTab = terminalTabs.addWorkflowTab(
            action: action,
            slug: folderName,
            overridePermissionMode: currentConfig()?.workflows?[action]?.permissionMode
        )

        // Resolve the template (default or per-project override) into the
        // sequence of lines that need to be injected into claude's REPL.
        let lines = WorkflowCommandResolver.resolve(
            action: action,
            slug: folderName,
            specURL: IssueLayout.specURL(in: handle.url, folderName: folderName),
            promptURL: IssueLayout.promptURL(in: handle.url, folderName: folderName),
            override: currentConfig()?.workflows?[action]
        )
        guard !lines.isEmpty else { return }

        let session = workflowTab.session
        let slug = action.slug
        // CR (\r) is what the terminal sends on Enter. claude's TUI treats
        // \n as a multi-line continuation (Shift+Enter style) and only \r as
        // submit — strip embedded \r from each line first so a stray Enter
        // doesn't submit a partial block early, then append \r as the
        // terminator.
        let payloads = lines.map { line in
            line.replacingOccurrences(of: "\r", with: "") + "\r"
        }

        workflowTask = Task { @MainActor in
            // Single inject call covers every line: consumePending() runs
            // exactly once at entry so the prior line can never be silently
            // drained between iterations (see TerminalClaudeSession.injectLines).
            let result = await session.injectLines(payloads)
            switch result {
            case .sessionExited:
                Self.log.info(
                    "runWorkflow: session exited mid-inject for \(slug, privacy: .public)."
                )
            case .timedOut:
                Self.log.warning(
                    "runWorkflow: session never reached .running within 5s; abort inject for \(slug, privacy: .public)."
                )
            case .injected, .cancelled:
                break
            }
        }
    }

    private func currentConfig() -> ProjectConfig? {
        if case .loaded(let config) = model.state { return config }
        return nil
    }

    private static let log = Logger(subsystem: "com.plumage", category: "runWorkflow")

    private func refreshGitActions() {
        let active = isLoaded && gitModel.repoState.isGitRepo
        if active {
            if commitAction == nil {
                commitAction = EditorAction {
                    showCommitSheet = true
                }
            }
            if pushAction == nil {
                pushAction = EditorAction {
                    syncOperation = .push
                    showSyncSheet = true
                }
            }
            if pullAction == nil {
                pullAction = EditorAction {
                    syncOperation = .pull
                    showSyncSheet = true
                }
            }
        } else {
            commitAction = nil
            pushAction = nil
            pullAction = nil
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
