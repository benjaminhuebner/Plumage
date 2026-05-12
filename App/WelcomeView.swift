import SwiftUI

struct WelcomeView: View {
    @Environment(RecentProjects.self) private var recentProjects

    var onOpenProject: () -> Void = {}
    var onOpenRecent: (RecentItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            openSection
            recentSection
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plumage")
                .font(.largeTitle.weight(.semibold))
            Text("Open a Plumage project to get started.")
                .foregroundStyle(.secondary)
        }
    }

    private var openSection: some View {
        Button(action: onOpenProject) {
            Label("Open Project…", systemImage: "folder")
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.headline)
            if recentProjects.items.isEmpty {
                Text("No recent projects yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                recentList
            }
        }
    }

    private var recentList: some View {
        List(recentProjects.items) { item in
            Button {
                onOpenRecent(item)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
        .frame(minHeight: 200)
    }
}

#Preview("Empty") {
    WelcomeView()
        .environment(RecentProjects(storeURL: previewStoreURL()))
}

#Preview("Populated") {
    let recents = RecentProjects(storeURL: previewStoreURL())
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Plumage"), name: "Plumage")
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Other"), name: "Other")
    return WelcomeView()
        .environment(recents)
}

@MainActor
private func previewStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PlumagePreview-\(UUID().uuidString).json")
}
