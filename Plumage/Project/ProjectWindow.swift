import SwiftUI
import os

struct ProjectWindow: View {
    let handle: ProjectHandle

    @State private var model = ProjectModel()
    @State private var kanban = ProjectKanbanModel()
    @State private var navigator = NavigatorModel()
    @State private var pinnedFiles = PinnedFilesModel()
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
    // Previously the dock panel hosted a Chat/Terminal mode switcher whose
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
    @State private var workflowLauncher = WorkflowLauncher()
    // SidebarFileWatcher signals on FSEvents for the project root; the
    // consumer task below reloads `navigator.rootNodes` so external mutations
    // (a `claude` subprocess creating a file under .claude/, the user dropping
    // a doc via Finder, …) show up in the sidebar without a manual refresh.
    @State private var sidebarFileWatcher: SidebarFileWatcher?
    @State private var sidebarFileWatcherTask: Task<Void, Never>?
    // Identity for this window's QuitCoordinator registration (⌘Q flush).
    @State private var quitHandlerID = UUID()

    @Environment(\.processRunner) private var processRunner
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RecentProjects.self) private var recentProjects
    @FocusedValue(\.issueDetailBackToBoard) private var backToBoardAction: EditorAction?

    init(handle: ProjectHandle) {
        self.handle = handle
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        let stateDirectory = Self.resolveStateDirectory(for: handle.url)
        self._session = State(
            initialValue: ClaudeSession(
                cwd: handle.url, binaryURL: binary, stateDirectory: stateDirectory)
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
        // drops the user's terminal history. Accepted trade-off.
        let initialTerminalSession = TerminalClaudeSession(
            cwd: handle.url, binaryURL: binary, stateDirectory: stateDirectory,
            persistConversationID: false
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

    // CCI never resolves bundles itself — the caller resolves here, at the open
    // boundary, and passes the directory in.
    private static func resolveStateDirectory(for root: URL) -> URL {
        guard let bundle = try? BundleResolver.findBundle(in: root) else {
            // Open always resolves a bundle before a handle exists, so this is
            // unreachable in practice. Assert rather than silently writing
            // session state to a location the project `.gitignore` doesn't cover.
            assertionFailure("No .plumage bundle for opened project at \(root.path)")
            return root
        }
        LegacySessionStateMigration.migrate(root: root, bundle: bundle)
        return bundle
    }

    var body: some View {
        baseStack
            .environment(kanban)
            .environment(navigator)
            .environment(pinnedFiles)
            .environment(\.openCreateIssue) { status in
                createInitialStatus = status
                showCreateSheet = true
            }
            // minHeight=620: dock panel is 560pt + 16pt bottom padding + ~28pt
            // titlebar = 604pt minimum vertical room; round up for safe-area
            // margin. Lower values clip the panel's close button behind the
            // titlebar.
            .frame(minWidth: 1100, minHeight: 620)
            // Per-project autosave name: a single shared name makes every
            // project window land on the last-moved frame.
            .background(
                WindowFrameAutosaver(autosaveName: "plumage.project.window.\(handle.url.path)")
            )
            .navigationTitle(displayTitle)
            .navigationDocument(handle.url)
            .focusedSceneValue(\.createIssueInDefaultColumn, createIssueAction)
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
                if let restored = Self.restoredRoute(
                    from: persistedRouteData, projectURL: handle.url)
                {
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
                let initialConfig: ProjectConfig?
                do {
                    initialConfig = try ConfigLoader.load(at: handle.url)
                } catch {
                    // Sessions fall back to default models; model.reload below
                    // surfaces the failure in the UI — but leave a trace for
                    // the silent window-reuse path.
                    Self.log.error(
                        "Window task: config load failed for \(handle.url.path, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    initialConfig = nil
                }
                let chatModel =
                    initialConfig?.models?.chat ?? ModelsConfig.chatDefault
                let terminalsModel =
                    initialConfig?.models?.terminals ?? ModelsConfig.terminalsDefault
                // Re-resolve the bundle for the (possibly new) handle — the
                // window may have been reused for a different project.
                let stateDirectory = Self.resolveStateDirectory(for: handle.url)
                session = ClaudeSession.rebuilt(
                    for: handle.url, replacing: session,
                    stateDirectory: stateDirectory, modelChoice: chatModel
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
                        stateDirectory: stateDirectory,
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
                        workflowLauncher.cancel()
                    }
                }
                // ⌘Q runs through applicationShouldTerminate, where SwiftUI's
                // .onDisappear teardown isn't guaranteed to fire — register
                // the subprocess stop so quitting never orphans claude.
                QuitCoordinator.shared.register(quitHandlerID) { [weak session, weak terminalTabs] in
                    session?.stop()
                    terminalTabs?.stopAll()
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
                mountSidebarWatcher(projectURL: handle.url)
                async let xcodeDiscover: Void = xcodeRun.discover(projectURL: handle.url)
                async let usagePoll: Void = claudeUsage.startPolling(using: usageClient)
                async let statusPoll: Void = claudeStatus.startPolling(using: statusClient)
                // Load the persisted pin set (or seed defaults) BEFORE the
                // await-group below: that group includes the never-returning
                // poll loops (usagePoll/statusPoll), so anything sequenced
                // after it never runs. loadOrSeed reads the disk directly and
                // doesn't depend on navLoad, so running it here is fine.
                await pinnedFiles.loadOrSeed(projectURL: handle.url)
                // Must run before the tuple await below: the poll loops in it
                // never return, so anything sequenced after is dead code. The
                // `.onChange(of: isLoaded)` below re-runs it once load settles.
                refreshCreateIssueAction()
                _ = await (reload, run, detect, navLoad, xcodeDiscover, usagePoll, statusPoll)
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
                QuitCoordinator.shared.unregister(quitHandlerID)
                session.stop()
                terminalTabs.stopAll()
                workflowLauncher.cancel()
                xcodeRunController.cancelRun()
                gitModel.stop()
                sidebarFileWatcherTask?.cancel()
                sidebarFileWatcherTask = nil
                sidebarFileWatcher = nil
            }
            .onChange(of: selectedRoute) { _, new in
                persistedRouteData = Self.persistedRouteString(new, projectURL: handle.url)
                if case .issue = new {
                } else {
                    detailOriginRoute = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await navigator.reload(projectURL: handle.url)
                        // External changes while backgrounded surface as the
                        // reload's inode diff — re-point moved pins, drop gone.
                        pinnedFiles.apply(rewrites: navigator.externalRewrites)
                    }
                }
            }
            .onChange(of: navigator.routeRewrites) { _, rewrites in
                applyRouteRewrites(rewrites)
                // Pins follow the same rename/move/trash the sidebar emitted.
                // Applied unconditionally — applyRouteRewrites early-returns
                // when the selection isn't a file, but pins must update either
                // way.
                pinnedFiles.apply(rewrites: rewrites)
            }
            .sheet(isPresented: $showCreateSheet) {
                NavigationStack {
                    IssueDetailView(projectURL: handle.url, initialStatus: createInitialStatus)
                }
                // Sheets present in their own SwiftUI tree and don't inherit
                // the presenter's environment. IssueDetailView's
                // @Environment(ProjectKanbanModel.self) crashes without these.
                // openSpec stays deliberately unwired here (defaults to no-op):
                // the create sheet navigates via onIssueCreated + dismiss(),
                // never by routing the window behind itself.
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
                        onRecheck: {
                            Task { await indicator.detect(using: processRunner) }
                        },
                        isOpen: $isDockOpen
                    )
                }
                .navigationSplitViewColumnWidth(min: 50, ideal: 700, max: .infinity)
                .inspector(isPresented: $isTerminalInspectorOpen) {
                    TerminalInspectorView(tabsModel: terminalTabs, isOpen: isTerminalInspectorOpen)
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
                .accessibilityValue(isTerminalInspectorOpen ? "Visible" : "Hidden")
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
                // changes.
                .id(selectedRoute)
                .environment(\.openSpec) { route in
                    if selectedRoute == .kanban, case .issue = route {
                        detailOriginRoute = .kanban
                    } else if case .issue = route {
                        // Issue→issue navigation: the new issue wasn't opened
                        // from the board, so the back-to-board affordance
                        // must not survive the hop.
                        detailOriginRoute = nil
                    }
                    selectedRoute = route
                }
                .environment(\.openCreateIssue) { status in
                    createInitialStatus = status
                    showCreateSheet = true
                }
                .environment(\.dismissToOrigin, backToOriginAction)
                .environment(\.runWorkflow, runWorkflow(_:folderName:issueType:))
                .environment(\.workflowCommandIsEmpty) { action, type in
                    WorkflowCommandResolver.filtersToEmpty(
                        action: action,
                        type: type,
                        override: currentConfig()?.workflows?[action]
                    )
                }
                .environment(\.onProjectConfigSaved) { saved in
                    // Mirror the disk-write into ProjectModel so the rest of
                    // the window (runWorkflow → currentConfig().workflows)
                    // and the live tabs model both see the picker change
                    // immediately, without waiting for a window reopen.
                    model.setLoaded(saved)
                    terminalTabs.modelsConfig = saved.models
                }
                .environment(\.onProjectRenamed) { config, newBundle in
                    // Live re-wire after a rename. The bundle folder moved but
                    // the project root — and thus the running chat's cwd and
                    // session-log key — did not, so the subprocess is untouched
                    // and the chat keeps going. We only: refresh the window
                    // title (config.name), repoint the chat session's bundle-
                    // derived id-store to the moved bundle for future writes,
                    // and update the project's name in Recents. Pins re-resolve
                    // the bundle by extension on every access, and terminal tabs
                    // are ephemeral, so neither needs repointing.
                    model.setLoaded(config)
                    session.repointSessionStore(toBundle: newBundle)
                    recentProjects.update(url: handle.url, name: config.name)
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
                        ?? kanban.lastDropError.map { "Drop failed: \($0)" }
                        ?? kanban.lastRemovalError.map { "Remove failed: \($0)" }
                        ?? kanban.boardError
                )
            }
            // Derived isPresented binding is the standard confirmationDialog
            // shape; the kanban model owns the pending state so the card
            // context menus (board + sidebar) share one dialog.
            .confirmationDialog(
                removalDialogTitle,
                isPresented: Binding(
                    get: { kanban.pendingRemoval != nil },
                    set: { if !$0 { kanban.cancelPendingRemoval() } }
                ),
                presenting: kanban.pendingRemoval
            ) { removal in
                switch removal.kind {
                case .archive:
                    Button("Archive") {
                        kanban.confirmRemoval(removal, projectURL: handle.url)
                    }
                case .trash:
                    Button("Move to Trash", role: .destructive) {
                        kanban.confirmRemoval(removal, projectURL: handle.url)
                    }
                }
            } message: { removal in
                switch removal.kind {
                case .archive:
                    Text(
                        "The issue folder moves to .claude/issues/archive/. "
                            + "Restoring means moving it back in Finder."
                    )
                case .trash:
                    Text("You can restore it from the Trash.")
                }
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't open this project.")
                    .font(.headline)
                Text(Self.message(for: error))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Try Again") {
                        Task { await model.reload(at: handle.url) }
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([handle.url])
                    }
                }
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var displayTitle: String {
        if case .loaded(let config) = model.state { return config.name }
        return handle.url.lastPathComponent
    }

    private var removalDialogTitle: String {
        guard let removal = kanban.pendingRemoval else { return "" }
        switch removal.kind {
        case .archive: return "Archive \"\(removal.folderName)\"?"
        case .trash: return "Move \"\(removal.folderName)\" to Trash?"
        }
    }

    private var backToOriginAction: (() -> Void)? {
        guard let origin = detailOriginRoute, origin == .kanban else { return nil }
        return { selectedRoute = .kanban }
    }

    // Keeps the open detail pane in sync when the sidebar renames/moves/trashes
    // the file (or an ancestor folder of the file) currently shown. Moves
    // re-point the selection to the new path; removals fall back to the board.
    // `.issue` routes follow their folder under .claude/issues/ the same way.
    private func applyRouteRewrites(_ rewrites: [RouteRewrite]) {
        switch selectedRoute {
        case .projectFile(let current):
            applyFileRouteRewrites(rewrites, current: current)
        case .issue(let folderName):
            applyIssueRouteRewrites(rewrites, folderName: folderName)
        case .kanban, .projectSettings:
            return
        }
    }

    private func applyFileRouteRewrites(_ rewrites: [RouteRewrite], current: String) {
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, let new):
                if current == old {
                    selectedRoute = .projectFile(relativePath: new)
                    return
                }
                if current.hasPrefix(old + "/") {
                    selectedRoute = .projectFile(
                        relativePath: new + String(current.dropFirst(old.count)))
                    return
                }
            case .removed(let old):
                if current == old || current.hasPrefix(old + "/") {
                    selectedRoute = .kanban
                    return
                }
            }
        }
    }

    private func applyIssueRouteRewrites(_ rewrites: [RouteRewrite], folderName: String) {
        let issuesPrefix = ".claude/issues/"
        let issuePath = issuesPrefix + folderName
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, let new):
                guard old == issuePath || issuePath.hasPrefix(old + "/") else { continue }
                let renamed = new.hasPrefix(issuesPrefix) ? String(new.dropFirst(issuesPrefix.count)) : ""
                if old == issuePath, !renamed.isEmpty, !renamed.contains("/") {
                    selectedRoute = .issue(folderName: renamed)
                } else {
                    // Moved out of the issues directory (or an ancestor moved):
                    // the route can't follow — fall back to the board.
                    selectedRoute = .kanban
                }
                return
            case .removed(let old):
                if old == issuePath || issuePath.hasPrefix(old + "/") {
                    selectedRoute = .kanban
                    return
                }
            }
        }
    }

    // SceneStorage survives window reuse across projects — the payload is
    // prefixed with the project path, and the restore validates the target
    // still exists so deleted issues/files fall back to the board.
    private static func persistedRouteString(_ route: NavigatorRoute, projectURL: URL) -> String {
        projectURL.path + "\n" + route.persistedString
    }

    private static func restoredRoute(from data: String, projectURL: URL) -> NavigatorRoute? {
        let parts = data.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == projectURL.path,
            let route = NavigatorRoute(persistedString: String(parts[1]))
        else { return nil }
        return routeTargetExists(route, projectURL: projectURL) ? route : nil
    }

    private static func routeTargetExists(_ route: NavigatorRoute, projectURL: URL) -> Bool {
        let fm = FileManager.default
        switch route {
        case .kanban, .projectSettings:
            return true
        case .issue(let folderName):
            return fm.fileExists(
                atPath: IssueLayout.specURL(in: projectURL, folderName: folderName).path)
        case .projectFile(let rel):
            return fm.fileExists(atPath: projectURL.appendingPathComponent(rel).path)
        }
    }

    private var isLoaded: Bool {
        if case .loaded = model.state { return true }
        return false
    }

    private func runWorkflow(_ action: WorkflowAction, folderName: String, issueType: IssueType) {
        workflowLauncher.run(
            action: action,
            folderName: folderName,
            issueType: issueType,
            projectURL: handle.url,
            override: currentConfig()?.workflows?[action],
            tabs: terminalTabs,
            openInspector: { isTerminalInspectorOpen = true },
            showBanner: { navigator.showBanner($0) }
        )
    }

    // Replaces an existing watcher when the window swaps to a different
    // project. The consumer task ends when the AsyncStream is finished (via
    // the watcher's teardown in deinit) or when we cancel it explicitly.
    private func mountSidebarWatcher(projectURL: URL) {
        sidebarFileWatcherTask?.cancel()
        let watcher = SidebarFileWatcher(projectURL: projectURL)
        sidebarFileWatcher = watcher
        sidebarFileWatcherTask = Task { [events = watcher.events] in
            for await _ in events {
                await navigator.reload(projectURL: projectURL)
                // External rename/move/delete of a pinned file surfaces as the
                // reload's inode diff (`externalRewrites`): a moved file is
                // re-pointed, a deleted one dropped. Reading the property right
                // after the awaited reload is race-free — both run on the
                // MainActor and this loop body is sequential.
                pinnedFiles.apply(rewrites: navigator.externalRewrites)
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
        } else {
            if createIssueAction != nil { createIssueAction = nil }
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
        .environment(RecentProjects())
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
