import AppKit
import SwiftUI

@main
struct PlumageApp: App {
    @NSApplicationDelegateAdaptor(PlumageAppDelegate.self) private var appDelegate
    @State private var recentProjects = RecentProjects()
    @State private var migrationRequest = MigrationRequest()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        Window("Welcome to Plumage", id: "welcome") {
            WelcomeView(windowAlphaHidden: !appDelegate.pendingURLs.isEmpty)
                .containerBackground(.thickMaterial, for: .window)
                .task {
                    await recentProjects.load()
                    drainPendingURLs()
                }
                .onChange(of: appDelegate.pendingURLs) { _, _ in
                    drainPendingURLs()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.presented)
        .keyboardShortcut("0", modifiers: [.command, .shift])
        .commands {
            NewProjectCommand()
        }
        .environment(recentProjects)
        .environment(migrationRequest)

        // `.commandsRemoved()` suppresses the auto "New Project" Window-menu
        // item; File > New (NewProjectCommand) is the intended entry point.
        Window("New Project", id: "new-project") {
            NewProjectWindowView()
                .environment(recentProjects)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Window("Migrate Project", id: "migrate-project") {
            MigrateProjectWindowView()
                .environment(recentProjects)
                .environment(migrationRequest)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        WindowGroup("Project", for: ProjectHandle.self) { $handle in
            if let handle {
                ProjectWindow(handle: handle)
                    .onChange(of: appDelegate.pendingURLs) { _, _ in
                        drainPendingURLs()
                    }
            } else {
                EmptyView()
                    .onAppear {
                        assertionFailure("Project window opened without a handle")
                    }
            }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            OpenProjectMenuCommand(recentProjects: recentProjects)
            NewIssueCommand()
            SpecEditorCommands()
            GitCommand()
            TerminalCommand()
        }
        .restorationBehavior(.disabled)
        .environment(recentProjects)
        .environment(migrationRequest)

        Settings {
            AppSettingsView()
        }
    }

    private func drainPendingURLs() {
        for url in appDelegate.consumePendingURLs() {
            OpenProjectCommand.openFromBundleURL(
                url,
                recentProjects: recentProjects,
                openWindow: openWindow,
                dismissWindow: dismissWindow
            )
        }
    }
}

@Observable
@MainActor
final class PlumageAppDelegate: NSObject, NSApplicationDelegate {
    private(set) var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
    }

    func consumePendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs = []
        return urls
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sync Plumage's bundled claude theme so the embedded terminal renders
        // without opaque block backgrounds. Off-main: installIfNeeded is
        // nonisolated pure file I/O and on iCloud Drive / NFS homes the writes
        // can take tens of milliseconds — no reason to block the launch path.
        // Failure is best-effort and swallowed inside the installer.
        Task.detached(priority: .utility) {
            ClaudeThemeInstaller.installIfNeeded()
        }
    }
}
