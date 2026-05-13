import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(RecentProjects.self) private var recentProjects
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: 460)
            rightPane
        }
        .frame(width: 860, height: 520)
        .background(WindowChromeCustomizer())
    }

    private var leftPane: some View {
        VStack(spacing: 18) {
            Spacer()
            appIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
            VStack(spacing: 4) {
                Text("Welcome to Plumage")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Version \(Self.appVersionString)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer().frame(height: 8)
            VStack(alignment: .leading, spacing: 8) {
                actionRow(
                    systemImage: "folder.badge.plus",
                    title: "Open a Project…",
                    subtitle: "Pick a folder with .plumage/config.json"
                ) {
                    OpenProjectCommand.openWithPicker(
                        recentProjects: recentProjects,
                        openWindow: openWindow,
                        dismissWindow: dismissWindow
                    )
                }
            }
            .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rightPane: some View {
        Group {
            if recentProjects.items.isEmpty {
                emptyState
            } else {
                List(recentProjects.items) { item in
                    RecentRow(item: item)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .contentShape(Rectangle())
                        .onTapGesture { open(item) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.05))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
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

    @ViewBuilder
    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    nonisolated static let appVersionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty || build == version { return version }
        return "\(version) (\(build))"
    }()
}

private struct RecentRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Text((item.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct WindowChromeCustomizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ChromeCustomizingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeCustomizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
        }
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
