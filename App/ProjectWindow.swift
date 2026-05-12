import SwiftUI

struct ProjectWindow: View {
    let handle: ProjectHandle

    @State private var state: LoadState = .loading
    @State private var issues: [Issue] = []

    enum LoadState {
        case loading
        case loaded(ProjectConfig)
        case failed(ConfigLoader.LoadError)
    }

    var body: some View {
        content
            .frame(minWidth: 720, minHeight: 480)
            .navigationTitle(displayTitle)
            .task(id: handle.url) { reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .loaded(let config):
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.name)
                        .font(.system(size: 32, weight: .semibold))
                    Text(handle.url.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                IssueListView(issues: issues, padding: config.issueIdPadding ?? 5)
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
        if case .loaded(let config) = state { return config.name }
        return handle.url.lastPathComponent
    }

    private func reload() {
        do {
            let config = try ConfigLoader.load(at: handle.url)
            state = .loaded(config)
            issues = IssueDiscovery.discoverIssues(in: handle.url)
        } catch let error as ConfigLoader.LoadError {
            state = .failed(error)
            issues = []
        } catch {
            state = .failed(.invalidJSON(message: error.localizedDescription))
            issues = []
        }
    }

    static func message(for error: ConfigLoader.LoadError) -> String {
        switch error {
        case .noConfigFile(let folder):
            return "No Plumage project at \(folder.path)."
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
    let plumage = dir.appendingPathComponent(".plumage")
    try? FileManager.default.createDirectory(at: plumage, withIntermediateDirectories: true)
    let config = """
        {
          "name": "Plumage",
          "schemaVersion": 2,
          "issueIdPadding": 5
        }
        """
    try? config.write(
        to: plumage.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    return dir
}
