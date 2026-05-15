import SwiftUI

struct ProjectWindow: View {
    let handle: ProjectHandle

    @State private var model = ProjectModel()
    @State private var kanban = ProjectKanbanModel()
    @State private var navigationPath = NavigationPath()
    @State private var indicator = StatusIndicatorModel()

    @Environment(\.processRunner) private var processRunner

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationDestination(for: SpecRoute.self) { route in
                    switch route {
                    case .spec(let folderName):
                        IssueDetailView(projectURL: handle.url, folderName: folderName)
                    case .rawEditor(let folderName):
                        SpecEditorView(projectURL: handle.url, folderName: folderName)
                            .navigationTitle("Raw: \(folderName)")
                    case .createIssue(let initialStatus):
                        IssueDetailView(projectURL: handle.url, initialStatus: initialStatus)
                    }
                }
        }
        .environment(kanban)
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(displayTitle)
        .focusedSceneValue(
            \.createIssueInDefaultColumn,
            isLoaded
                ? {
                    navigationPath.append(SpecRoute.createIssue(initialStatus: .draft))
                }
                : nil
        )
        .task(id: handle.url) {
            async let reload: Void = model.reload(at: handle.url)
            async let run: Void = kanban.run(projectURL: handle.url)
            async let detect: Void = indicator.detect(using: processRunner)
            _ = await (reload, run, detect)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .loaded(let config):
            VStack(alignment: .leading, spacing: 16) {
                ProjectHeader(
                    title: config.name,
                    path: handle.url.path,
                    indicatorState: indicator.state
                )
                KanbanView(
                    grouped: kanban.groupedIssues,
                    padding: config.issueIdPadding ?? 5,
                    projectURL: handle.url
                )
                .environment(\.kanbanHighlightedID, kanban.highlightedIssueID)
                .environment(\.openSpec) { route in
                    navigationPath.append(route)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
