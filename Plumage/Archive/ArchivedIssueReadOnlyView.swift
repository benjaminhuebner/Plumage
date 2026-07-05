import SwiftUI

struct ArchivedIssueReadOnlyView: View {
    let projectURL: URL
    let folderName: String

    @Environment(ProjectKanbanModel.self) private var kanban
    @Environment(\.openSpec) private var openSpec

    @State private var content: String?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            documentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .onChange(of: kanban.lastRemovalCompleted) { _, completed in
            // The card this view shows just left the archive (unarchived or
            // trashed) — fall back to the list instead of a stale spec.
            if completed == folderName { openSpec(.archive) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                openSpec(.archive)
            } label: {
                Label("Archive", systemImage: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .help("Back to Archive")
            Text(folderName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("Read-only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var documentBody: some View {
        if let content {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Can't open this spec", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        let url = IssueLayout.archivedSpecURL(in: projectURL, folderName: folderName)
        let outcome = await Task.detached(priority: .userInitiated) { () -> LoadOutcome in
            do {
                return .loaded(try String(contentsOf: url, encoding: .utf8))
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
        switch outcome {
        case .loaded(let text): content = text
        case .failed(let message): loadError = message
        }
    }

    private enum LoadOutcome: Sendable {
        case loaded(String)
        case failed(String)
    }
}
