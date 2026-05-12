import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(RecentProjects.self) private var recentProjects
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: 320)
            Divider()
            rightPane
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 460, idealHeight: 480)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                appIcon
                    .resizable()
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 8)
                Text("Welcome to Plumage")
                    .font(.system(size: 26, weight: .semibold))
                Text("Version \(appVersionString)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.horizontal, 28)

            Spacer(minLength: 24)

            Button {
                OpenProjectCommand.openWithPicker(
                    recentProjects: recentProjects,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open a Project…")
                            .font(.system(size: 14, weight: .medium))
                        Text("Choose a folder with .plumage/config.json.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var rightPane: some View {
        Group {
            if recentProjects.items.isEmpty {
                emptyState
            } else {
                List(recentProjects.items) { item in
                    RecentRow(item: item)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(item) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Recent Projects")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Recent projects will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func open(_ item: RecentItem) {
        OpenProjectCommand.openConfirmed(
            url: item.url,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }

    private var appIcon: Image {
        Image(systemName: "bird.fill")
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty || build == version { return version }
        return "\(version) (\(build))"
    }
}

private struct RecentRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text((item.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

#Preview("Empty") {
    WelcomeView()
        .environment(RecentProjects(storeURL: previewStoreURL()))
}

#Preview("Populated") {
    let recents = RecentProjects(storeURL: previewStoreURL())
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Plumage"), name: "Plumage")
    recents.add(
        url: URL(fileURLWithPath: "/Users/dev/AnotherSampleProject"),
        name: "Another Sample Project"
    )
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Third"), name: "Third")
    return WelcomeView()
        .environment(recents)
}

@MainActor
private func previewStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PlumagePreview-\(UUID().uuidString).json")
}
