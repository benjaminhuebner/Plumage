import AppKit
import SwiftUI

struct WelcomeView: View {
    private static let leftPaneWidth: CGFloat = 473
    private static let windowWidth: CGFloat = 710
    private static let windowHeight: CGFloat = 429

    let windowAlphaHidden: Bool

    @Environment(RecentProjects.self) private var recentProjects
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showNewProject = false

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: Self.leftPaneWidth)
            rightPane
        }
        .sheet(isPresented: $showNewProject) {
            // Sheets present in their own SwiftUI tree and don't inherit the
            // presenter's environment; RecentProjects must be injected so the
            // post-create open path can record the project.
            NewProjectSheet()
                .environment(recentProjects)
        }
        // Lets the "New Project… ⌘N" menu command open the wizard while Welcome
        // is the focused scene.
        .focusedSceneValue(\.newProjectPresented, $showNewProject)
        // min/ideal pair instead of a hard width/height: a hard `.frame(width:height:)`
        // on a Window scene root historically wedged XCUITest auto-terminate
        // (notes.md 00002-open-project), and a non-resizable window also
        // truncates long recent-project paths with no way to widen. Min equals
        // Ideal so the default opening size is unchanged.
        .frame(
            minWidth: Self.windowWidth, idealWidth: Self.windowWidth,
            minHeight: Self.windowHeight, idealHeight: Self.windowHeight
        )
        .background(WindowChromeCustomizer(windowAlphaHidden: windowAlphaHidden))
    }

    private var leftPane: some View {
        VStack(spacing: 18) {
            Spacer()
            appIcon
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
                    systemImage: "plus.square.on.square",
                    title: "New Project…",
                    subtitle: "Scaffold a fresh Plumage project"
                ) {
                    showNewProject = true
                }
                actionRow(
                    systemImage: "folder.badge.plus",
                    title: "Open a Project…",
                    subtitle: "Pick a .plumage bundle or its parent folder"
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

    // NSApp.applicationIconImage falls back to the system "Application" icon
    // when the bundle has no AppIcon set yet (debug runs from Xcode). Sized
    // by the caller via .frame.
    private var appIcon: Image {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
    }

    nonisolated static let appVersionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty || build == version { return version }
        return "\(version) (\(build))"
    }()
}

#Preview("Empty") {
    WelcomeView(windowAlphaHidden: false)
        .environment(RecentProjects(storeURL: previewStoreURL()))
}

@MainActor
private func populatedRecents() -> RecentProjects {
    let recents = RecentProjects(storeURL: previewStoreURL())
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Plumage"), name: "Plumage")
    recents.add(
        url: URL(fileURLWithPath: "/Users/dev/AnotherSampleProject"),
        name: "Another Sample Project"
    )
    recents.add(url: URL(fileURLWithPath: "/Users/dev/Third"), name: "Third")
    return recents
}

#Preview("Populated") {
    WelcomeView(windowAlphaHidden: false)
        .environment(populatedRecents())
}

@MainActor
private func previewStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PlumagePreview-\(UUID().uuidString).json")
}
