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
    @State private var indicator = StatusIndicatorModel()
    @State private var claudeUsage = ClaudeUsageModel()
    @State private var claudeStatus = ClaudeStatusModel()
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
        // disk persistence, no reconcile pickup. Otherwise the main tab
        // could adopt a sibling claude session (e.g. a /plan or /implement
        // run) that happened to write the same log dir last.
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
                session = ClaudeSession.rebuilt(for: handle.url, replacing: session)
                // Window reused for a different handle: stop all existing
                // tabs and spin up a fresh tabs model with a new default tab.
                if terminalTabs.cwd != handle.url {
                    terminalTabs.stopAll()
                    let newBinary =
                        (try? ProductionProcessRunner.locateBinary())
                        ?? URL(filePath: "/dev/null")
                    let newInitial = TerminalClaudeSession(
                        cwd: handle.url, binaryURL: newBinary,
                        persistConversationID: false
                    )
                    terminalTabs = TerminalTabsModel(
                        cwd: handle.url,
                        binaryURL: newBinary,
                        initialSession: newInitial
                    )
                }
                // Chat shares the claude log dir with terminal; without this
                // exclude the terminal's reconcile would adopt chat's session
                // ID if chat happened to be the last writer. setShared also
                // propagates to the existing default-tab session.
                terminalTabs.setSharedExcludedSessionIDs { [weak session] in
                    guard let id = session?.conversationID else { return [] }
                    return [id]
                }
                session.attach()
                terminalTabs.activeSession?.attach()
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
                terminalTabs.stopAll()
                workflowTask?.cancel()
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
                .environment(\.runWorkflow, runWorkflow(_:folderName:body:))
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

    private func runWorkflow(_ action: WorkflowAction, folderName: String, body: String?) {
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

        // Cancel any prior inject still mid-sleep before its body enqueue.
        // Without this, a quick second click would: drain the prior slash
        // command from pendingInput (or find it already flushed), enqueue a
        // new command, and then the prior task would wake from its 800ms
        // sleep and tack its body onto whatever ran most recently.
        workflowTask?.cancel()
        isTerminalInspectorOpen = true

        // CR (\r) is what the terminal sends on Enter. claude's TUI treats
        // \n as a multi-line continuation (Shift+Enter style) and only \r as
        // submit — sending \n appended to the slash command just inserts a
        // blank line. Strip \r from the body so a stray Enter inside the
        // user's text doesn't submit a partial block early.
        let slashCommand = "/\(action.slug) \(folderName)\r"
        let followUp: String? = {
            guard action == .plan, let body else { return nil }
            return body.replacingOccurrences(of: "\r", with: "") + "\r"
        }()
        // Inject feeds the active tab; canCloseActiveTab guarantees we always
        // have one, so nil here is a defensive no-op rather than a real path.
        guard let session = terminalTabs.activeSession else {
            Self.log.debug(
                "runWorkflow: no active terminal tab; dropping inject for \(action.slug, privacy: .public)."
            )
            return
        }
        let slug = action.slug

        workflowTask = Task { @MainActor in
            let result = await session.inject(
                slashCommand: slashCommand, followUpBody: followUp)
            switch result {
            case .sessionExited:
                Self.log.info(
                    "runWorkflow: session exited before inject for \(slug, privacy: .public)."
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

    private static let log = Logger(subsystem: "com.plumage", category: "runWorkflow")

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
