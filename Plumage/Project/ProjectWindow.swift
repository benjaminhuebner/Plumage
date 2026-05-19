import SwiftUI

struct ProjectWindow: View {
    let handle: ProjectHandle

    @State private var model = ProjectModel()
    @State private var kanban = ProjectKanbanModel()
    @State private var navigator = NavigatorModel()
    @State private var selectedRoute: NavigatorRoute = .kanban
    @SceneStorage("nav.selection") private var persistedRouteData: String = ""
    @State private var showCreateSheet = false
    @State private var createInitialStatus: IssueStatus = .draft
    @State private var indicator = StatusIndicatorModel()
    @State private var session: ClaudeSession
    @SceneStorage("terminalShown") private var terminalShown = false

    @Environment(\.processRunner) private var processRunner
    @Environment(\.scenePhase) private var scenePhase

    init(handle: ProjectHandle) {
        self.handle = handle
        let binary =
            (try? ProductionProcessRunner.locateBinary())
            ?? URL(filePath: "/dev/null")
        self._session = State(
            initialValue: ClaudeSession(cwd: handle.url, binaryURL: binary)
        )
    }

    var body: some View {
        baseStack
            .environment(kanban)
            .environment(navigator)
            .frame(minWidth: 720, minHeight: 480)
            .navigationTitle(displayTitle)
            .focusedSceneValue(
                \.createIssueInDefaultColumn,
                isLoaded
                    ? {
                        createInitialStatus = .draft
                        showCreateSheet = true
                    }
                    : nil
            )
            .focusedSceneValue(\.terminalToggle, $terminalShown)
            .task(id: handle.url) {
                if let restored = NavigatorRoute(persistedString: persistedRouteData) {
                    selectedRoute = restored
                }
                async let reload: Void = model.reload(at: handle.url)
                async let run: Void = kanban.run(projectURL: handle.url)
                async let detect: Void = indicator.detect(using: processRunner)
                async let navLoad: Void = navigator.reload(projectURL: handle.url)
                _ = await (reload, run, detect, navLoad)
            }
            .onChange(of: selectedRoute) { _, new in
                persistedRouteData = new.persistedString
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
                .frame(minWidth: 720, minHeight: 600)
            }
    }

    @ViewBuilder
    private var baseStack: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            terminalShown.toggle()
                        } label: {
                            Label("Terminal", systemImage: "apple.terminal")
                        }
                        .help("Toggle Terminal (⌥⌘T)")
                    }
                }
        }
        .inspector(isPresented: $terminalShown) {
            TerminalPaneView(session: session, indicatorState: indicator.state)
                .inspectorColumnWidth(min: 320, ideal: 480, max: 900)
        }
        .onChange(of: terminalShown, initial: false) { _, newValue in
            // Synchronous: start/restart must happen before the inspector's
            // content renders to avoid a brief state-misalignment with what's
            // displayed. The "Modifying state during view update" warning this
            // can provoke is cosmetic — see TerminalPaneView's onChange for
            // the same trade-off.
            handleInspectorToggle(visible: newValue)
        }
    }

    private func handleInspectorToggle(visible: Bool) {
        if visible {
            switch session.state {
            case .idle: session.start()
            case .exited: session.restart()
            case .starting, .running: break
            }
        } else {
            session.stop()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        NavigatorSidebar(selection: $selectedRoute)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let config):
            VStack(alignment: .leading, spacing: 0) {
                ProjectHeader(
                    title: config.name,
                    path: handle.url.path,
                    indicatorState: indicator.state
                )
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
                    selectedRoute = route
                }
                .environment(\.openCreateIssue) { status in
                    createInitialStatus = status
                    showCreateSheet = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var isLoaded: Bool {
        if case .loaded = model.state { return true }
        return false
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
