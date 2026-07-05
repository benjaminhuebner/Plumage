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
    @State private var showAddRemoteSheet = false
    // Owned here (not built inline in the sheet closure) so the instance is
    // stable across ProjectWindow re-renders — otherwise each re-render made a
    // fresh model and the view showed one whose async remote load never ran.
    @State private var syncModel: GitSyncModel?
    @State private var addRemoteModel: AddRemoteModel?
    @State private var showImportIssuesSheet = false
    @State private var importIssuesModel: GitHubImportModel?
    @State private var githubOriginPresent = false
    @State private var commitAction: EditorAction?
    @State private var pushAction: EditorAction?
    @State private var pullAction: EditorAction?
    @State private var addRemoteAction: EditorAction?
    @State private var importIssuesAction: EditorAction?
    @State private var showTagSheet = false
    @State private var tagModel: GitTagModel?
    @State private var tagAction: EditorAction?
    @State private var showInitSheet = false
    @State private var initModel: GitInitModel?
    @State private var initAction: EditorAction?
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
    @AppStorage(ChatButtonPlacement.storageKey) private var chatButtonPlacement: ChatButtonPlacement = .floating
    @AppStorage(KeepMacAwakeSetting.storageKey) private var keepMacAwake: Bool =
        KeepMacAwakeSetting.defaultValue
    @State private var idleSleepGuard = IdleSleepGuard()
    @SceneStorage("inspector.terminal.open") private var isTerminalInspectorOpen = false
    @State private var windowContentWidth: CGFloat = 0
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
    @State private var runStatus = RunStatusModel()
    // SidebarFileWatcher signals on FSEvents for the project root; the
    // consumer task below reloads `navigator.rootNodes` so external mutations
    // (a `claude` subprocess creating a file under .claude/, the user dropping
    // a doc via Finder, …) show up in the sidebar without a manual refresh.
    @State private var sidebarFileWatcher: SidebarFileWatcher?
    @State private var sidebarFileWatcherTask: Task<Void, Never>?
    // Identity for this window's QuitCoordinator registration (⌘Q flush).
    @State private var quitHandlerID = UUID()

    @Environment(\.processRunner) private var processRunner
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.issueTypeCatalog) private var issueTypeCatalog
    @Environment(RecentProjects.self) private var recentProjects
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @FocusedValue(\.issueDetailBackToBoard) private var backToBoardAction: EditorAction?

    init(handle: ProjectHandle) {
        self.handle = handle
        let binary = Self.resolveClaudeBinary()
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

    // /dev/null keeps the sessions constructible; they fail visibly at attach.
    private static func resolveClaudeBinary() -> URL {
        do {
            return try ProductionProcessRunner.locateBinary()
        } catch {
            Self.log.error(
                "claude binary not found, falling back to /dev/null: \(String(describing: error), privacy: .public)"
            )
            return URL(filePath: "/dev/null")
        }
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
            .environment(runStatus)
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
            .focusedSceneValue(\.gitInitAction, initAction)
            .focusedSceneValue(\.gitCommitAction, commitAction)
            .focusedSceneValue(\.gitCreateTagAction, tagAction)
            .focusedSceneValue(\.gitPushAction, pushAction)
            .focusedSceneValue(\.gitPullAction, pullAction)
            .focusedSceneValue(\.gitAddRemoteAction, addRemoteAction)
            .focusedSceneValue(\.gitImportIssuesAction, importIssuesAction)
            .task(id: handle.url) {
                MainThreadHangSampler.shared.startIfEnabled()
                RunCompletionNotifier.shared.watchProjectRuns(root: handle.url)
                runStatus.start(projectURL: handle.url)
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
                let chatEffort =
                    initialConfig?.efforts?.chat ?? EffortsConfig.chatDefault
                let terminalsModel =
                    initialConfig?.models?.terminals ?? ModelsConfig.terminalsDefault
                let terminalsEffort =
                    initialConfig?.efforts?.terminals ?? EffortsConfig.terminalsDefault
                // Re-resolve the bundle for the (possibly new) handle — the
                // window may have been reused for a different project.
                let stateDirectory = Self.resolveStateDirectory(for: handle.url)
                session = ClaudeSession.rebuilt(
                    for: handle.url, replacing: session,
                    stateDirectory: stateDirectory, modelChoice: chatModel,
                    effortChoice: chatEffort
                )
                // Window reused for a different handle, OR the terminals
                // model preference changed in config: rebuild the tabs model
                // so the next-spawned default tab uses the right model.
                if terminalTabs.cwd != handle.url
                    || terminalTabs.mainSession.modelChoice != terminalsModel
                    || terminalTabs.mainSession.effortChoice != terminalsEffort
                {
                    terminalTabs.stopAll()
                    let newBinary = Self.resolveClaudeBinary()
                    let newInitial = TerminalClaudeSession(
                        cwd: handle.url, binaryURL: newBinary,
                        stateDirectory: stateDirectory,
                        modelChoice: terminalsModel,
                        effortChoice: terminalsEffort,
                        persistConversationID: false
                    )
                    terminalTabs = TerminalTabsModel(
                        cwd: handle.url,
                        binaryURL: newBinary,
                        initialSession: newInitial,
                        modelsConfig: initialConfig?.models,
                        effortsConfig: initialConfig?.efforts
                    )
                } else {
                    terminalTabs.modelsConfig = initialConfig?.models
                    terminalTabs.effortsConfig = initialConfig?.efforts
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
                QuitCoordinator.shared.register(quitHandlerID) {
                    [weak session, weak terminalTabs, idleSleepGuard] in
                    session?.stop()
                    terminalTabs?.stopAll()
                    idleSleepGuard.update(shouldHold: false)
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
                await refreshGithubOrigin()
            }
            .onChange(of: isLoaded) { _, _ in refreshCreateIssueAction() }
            .onChange(of: isLoaded) { _, _ in refreshGitActions() }
            .onChange(of: gitModel.repoState.isGitRepo) { _, _ in
                refreshGitActions()
                Task { await refreshGithubOrigin() }
            }
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
            // initial: true also holds for a window that opens onto an
            // already-running session, not only on later transitions.
            .onChange(of: shouldHoldAwake, initial: true) { _, hold in
                idleSleepGuard.update(shouldHold: hold)
            }
            .onDisappear {
                runStatus.stop()
                RunCompletionNotifier.shared.unwatchProjectRuns(root: handle.url)
                QuitCoordinator.shared.unregister(quitHandlerID)
                idleSleepGuard.update(shouldHold: false)
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
            .onChange(of: controlActiveState) { _, state in
                kanban.setActive(state != .inactive)
                Task {
                    let reloaded = await navigator.setActive(
                        state != .inactive, projectURL: handle.url)
                    // The reconciled reload re-points moved pins / drops gone ones.
                    if reloaded { pinnedFiles.apply(rewrites: navigator.externalRewrites) }
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
            .onChange(of: navigator.externalRewrites) { _, rewrites in
                // External (FSEvent-driven) renames/moves/deletes already update
                // pins on reload; the route must follow them too or it strands
                // in a conflict on a vanished folder.
                applyRouteRewrites(rewrites)
            }
            .sheet(isPresented: $showCreateSheet) {
                NavigationStack {
                    IssueDetailView(projectURL: handle.url, initialStatus: createInitialStatus)
                }
                // A sheet runs in its own SwiftUI tree, so pass the envs
                // IssueDetailView reads or it crashes; openSpec is left absent so
                // create-success just dismisses and the new card arrives via FSEvents.
                .environment(kanban)
                .environment(navigator)
                .environment(runStatus)
                .environment(\.onIssueCreated) { _ in
                    showCreateSheet = false
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
                if let syncModel {
                    GitSyncView(
                        model: syncModel,
                        onDismiss: { showSyncSheet = false },
                        onAddAccount: {
                            settingsNavigation.selectedTab = .accounts
                            SettingsOpener.open()
                        }
                    )
                }
            }
            .sheet(isPresented: $showAddRemoteSheet) {
                if let addRemoteModel {
                    AddRemoteSheet(
                        model: addRemoteModel,
                        onDismiss: { showAddRemoteSheet = false },
                        onAddAccount: {
                            settingsNavigation.selectedTab = .accounts
                            SettingsOpener.open()
                        }
                    )
                }
            }
            .sheet(isPresented: $showImportIssuesSheet) {
                if let importIssuesModel {
                    GitHubImportSheet(
                        model: importIssuesModel,
                        adoptedNumbers: kanban.adoptedGitHubNumbers,
                        onDismiss: { showImportIssuesSheet = false },
                        onConnectAccount: {
                            settingsNavigation.selectedTab = .accounts
                            SettingsOpener.open()
                        }
                    )
                }
            }
            .sheet(isPresented: $showTagSheet) {
                if let tagModel {
                    GitTagSheet(model: tagModel, onDismiss: { showTagSheet = false })
                }
            }
            .sheet(isPresented: $showInitSheet) {
                if let initModel {
                    GitInitSheet(
                        model: initModel,
                        onDismiss: { showInitSheet = false },
                        onInitialized: {
                            gitModel.rescan(repoURL: handle.url)
                            refreshGitActions()
                            Task { await refreshGithubOrigin() }
                        })
                }
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
                        showsButton: chatButtonPlacement == .floating,
                        isOpen: $isDockOpen
                    )
                }
                // min 360 keeps the status bar readable: the inspector sash and
                // the window minimum both honor the detail column's floor.
                .navigationSplitViewColumnWidth(min: 360, ideal: 700, max: .infinity)
                .inspector(isPresented: $isTerminalInspectorOpen) {
                    TerminalInspectorView(tabsModel: terminalTabs, isOpen: isTerminalInspectorOpen)
                        // Sash drag is safe again: TerminalResizeContainer keeps
                        // SwiftTerm's resize out of the AppKit layout pass.
                        .inspectorColumnWidth(
                            min: TerminalInspectorWidthPolicy.minWidth(
                                forContentWidth: windowContentWidth),
                            ideal: TerminalInspectorWidthPolicy.idealWidth(
                                forContentWidth: windowContentWidth),
                            max: TerminalInspectorWidthPolicy.maxWidth(
                                forContentWidth: windowContentWidth)
                        )
                }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            TerminalInspectorWidthPolicy.quantizedContentWidth(proxy.size.width)
        } action: { width in
            windowContentWidth = width
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
                    Image(systemName: "apple.terminal")
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
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
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
                .environment(\.jumpToRunTerminal, jumpToRunTerminal(_:))
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
                    terminalTabs.effortsConfig = saved.efforts
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
                // detail column; ProjectStatusBar sits below the clip.
                .clipped()
                ProjectStatusBar(
                    indicatorState: indicator.state,
                    usageModel: claudeUsage,
                    statusModel: claudeStatus,
                    repoState: gitModel.repoState,
                    gitModel: gitModel,
                    banner: navigator.dropRejectMessage
                        ?? kanban.lastDropError.map { "Drop failed: \($0)" }
                        ?? kanban.lastRemovalError.map { "Remove failed: \($0)" }
                        ?? kanban.boardError,
                    queueEntries: QueueDisplayBuilder.entries(from: runStatus.queuedRuns) {
                        terminalTabs.findWorkflowTab(action: .implement, slug: $0) != nil
                    },
                    onCancelQueued: cancelQueuedRun(_:),
                    chatIsWorking: session.awaitingResponse,
                    onToggleChat: chatButtonPlacement == .statusBar
                        ? { isDockOpen.toggle() } : nil
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
            // Side-effect-only setter: false routes to the launcher's cancel,
            // no mirrored local state to keep in sync.
            .confirmationDialog(
                "An implement run is already active",
                isPresented: Binding(
                    get: { workflowLauncher.pendingImplement != nil },
                    set: { if !$0 { workflowLauncher.cancelPendingImplement() } }
                ),
                presenting: workflowLauncher.pendingImplement
            ) { _ in
                Button("Start in Worktree") {
                    workflowLauncher.confirmPendingImplement(.worktree)
                }
                Button("Wait in Queue") {
                    workflowLauncher.confirmPendingImplement(.wait)
                }
                Button("Cancel", role: .cancel) {
                    workflowLauncher.cancelPendingImplement()
                }
            } message: { pending in
                Text(
                    "\(pending.blocker) is running in this checkout. "
                        + "Start \(pending.slug) in its own worktree and run in parallel, "
                        + "or wait in line — a queued run starts by itself when it's its turn."
                )
            }
            .sheet(
                item: Binding(
                    get: { gitModel.pendingBranchMerge },
                    set: { gitModel.pendingBranchMerge = $0 }
                )
            ) { request in
                BranchMergeSheet(
                    request: request,
                    isMerging: gitModel.isMerging,
                    error: gitModel.lastMergeError,
                    noticeMessage: gitModel.lastMergeNotice,
                    onDismissError: { gitModel.clearMergeError() },
                    onMerge: { mode, subject, deleteSource in
                        Task {
                            let merged = await gitModel.mergeBranch(
                                source: request.source, target: request.target,
                                mode: mode, subject: subject, deleteSource: deleteSource)
                            // A non-fatal notice keeps the sheet open so the
                            // user sees it; plain success just closes.
                            if merged, gitModel.lastMergeNotice == nil {
                                gitModel.pendingBranchMerge = nil
                            }
                        }
                    },
                    onClose: {
                        gitModel.clearMergeError()
                        gitModel.clearMergeNotice()
                        gitModel.pendingBranchMerge = nil
                    }
                )
                .interactiveDismissDisabled(gitModel.isMerging)
            }
            .alert(
                "Worktree setup failed",
                isPresented: Binding(
                    get: { workflowLauncher.worktreeProvisionError != nil },
                    set: { if !$0 { workflowLauncher.dismissWorktreeProvisionError() } }
                ),
                presenting: workflowLauncher.worktreeProvisionError
            ) { _ in
                Button("Try Again") { workflowLauncher.retryWorktreeProvision() }
                Button("Cancel", role: .cancel) {
                    workflowLauncher.dismissWorktreeProvisionError()
                }
            } message: { error in
                Text(error)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't open this project.")
                    .font(.headline)
                Text(error.localizedDescription)
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
        if case .loaded(let config) = model.state { config.name } else { handle.url.lastPathComponent }
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
        cancelStalePendingImplement(rewrites)
        if let rewritten = NavigatorRoute.rewritten(selectedRoute, by: rewrites) {
            selectedRoute = rewritten
        }
    }

    // An externally renamed/trashed issue would leave the implement-confirm
    // dialog offering a stale slug — close the dialog instead.
    private func cancelStalePendingImplement(_ rewrites: [RouteRewrite]) {
        guard let pending = workflowLauncher.pendingImplement else { return }
        let issuePath = IssueLayout.issuesRelativePrefix + pending.slug
        for rewrite in rewrites {
            switch rewrite {
            case .moved(let old, _), .removed(let old):
                if old == issuePath || issuePath.hasPrefix(old + "/") {
                    workflowLauncher.cancelPendingImplement()
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
        if case .loaded = model.state { true } else { false }
    }

    private var shouldHoldAwake: Bool {
        keepMacAwake && anyClaudeActive
    }

    private var anyClaudeActive: Bool {
        isLive(session.state) || terminalTabs.tabs.contains { isLive($0.session.state) }
    }

    private func isLive(_ state: ClaudeSession.State) -> Bool {
        switch state {
        case .starting, .running: true
        case .idle, .exited: false
        }
    }

    private func isLive(_ state: TerminalClaudeSession.State) -> Bool {
        switch state {
        case .starting, .running: true
        case .idle, .exited: false
        }
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

    private func cancelQueuedRun(_ slug: String) {
        guard let tab = terminalTabs.findWorkflowTab(action: .implement, slug: slug) else {
            return
        }
        // Closing the tab kills the waiting session; deleting the queue file
        // alone would not stick — wait-for-turn re-enqueues on its next poll.
        terminalTabs.closeTab(id: tab.id)
        runStatus.scheduleRefresh()
        // No FSEvent marks the pid death; re-scan once the SIGTERM landed.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            runStatus.scheduleRefresh()
        }
    }

    private func jumpToRunTerminal(_ folderName: String) {
        guard let tab = terminalTabs.findWorkflowTab(action: .implement, slug: folderName) else {
            navigator.showBanner("This run has no terminal tab in this window.")
            return
        }
        isTerminalInspectorOpen = true
        terminalTabs.selectedTabID = tab.id
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
                let reloaded = await navigator.reloadOrDefer(projectURL: projectURL)
                // Pins follow the reload's inode diff; valid only when it ran.
                if reloaded { pinnedFiles.apply(rewrites: navigator.externalRewrites) }
            }
        }
    }

    private func currentConfig() -> ProjectConfig? {
        if case .loaded(let config) = model.state { config } else { nil }
    }

    private func makeSyncModel(operation: GitSyncOperation) -> GitSyncModel {
        GitSyncModel(
            repoURL: handle.url,
            operation: operation,
            currentBranch: gitModel.repoState.branchName,
            boundAccountID: currentConfig()?.githubAccountID
        )
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
                    // One sync sheet at a time: re-invoking while it's open would
                    // swap in a fresh model whose id-less .task never re-fires.
                    guard !showSyncSheet else { return }
                    syncModel = makeSyncModel(operation: .push)
                    showSyncSheet = true
                }
            }
            if pullAction == nil {
                pullAction = EditorAction {
                    guard !showSyncSheet else { return }
                    syncModel = makeSyncModel(operation: .pull)
                    showSyncSheet = true
                }
            }
            if addRemoteAction == nil {
                addRemoteAction = EditorAction {
                    guard !showAddRemoteSheet else { return }
                    addRemoteModel = AddRemoteModel(repoURL: handle.url)
                    showAddRemoteSheet = true
                }
            }
            if tagAction == nil {
                tagAction = EditorAction {
                    guard !showTagSheet else { return }
                    tagModel = GitTagModel(repoURL: handle.url)
                    showTagSheet = true
                }
            }
        } else {
            commitAction = nil
            pushAction = nil
            pullAction = nil
            addRemoteAction = nil
            tagAction = nil
        }
        let importEnabled = active && githubOriginPresent
        if importEnabled {
            if importIssuesAction == nil {
                importIssuesAction = EditorAction {
                    guard !showImportIssuesSheet else { return }
                    importIssuesModel = makeImportModel()
                    Task { await kanban.refreshAdoptedGitHubNumbers() }
                    showImportIssuesSheet = true
                }
            }
        } else {
            importIssuesAction = nil
        }

        let canInit = isLoaded && !gitModel.repoState.isGitRepo
        if canInit {
            if initAction == nil {
                initAction = EditorAction {
                    guard !showInitSheet else { return }
                    initModel = GitInitModel(
                        repoURL: handle.url,
                        projectName: currentConfig()?.name ?? handle.url.lastPathComponent)
                    showInitSheet = true
                }
            }
        } else {
            initAction = nil
        }
    }

    private func makeImportModel() -> GitHubImportModel {
        GitHubImportModel(
            projectURL: handle.url,
            boundAccountID: currentConfig()?.githubAccountID,
            defaultIssueType: issueTypeCatalog.defaultType,
            openInEditor: { folderName in
                if selectedRoute == .kanban { detailOriginRoute = .kanban }
                selectedRoute = .issue(folderName: folderName)
            })
    }

    private func refreshGithubOrigin() async {
        guard gitModel.repoState.isGitRepo else {
            githubOriginPresent = false
            refreshGitActions()
            return
        }
        let runner = GitRemoteURLRunner(runner: ProductionGitProcessRunner())
        let remote = await runner.originRemote(for: handle.url)
        githubOriginPresent = remote?.host == GitHubAccount.defaultHost && remote?.repo != nil
        refreshGitActions()
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
