import AppKit
import SwiftUI

@main
struct PlumageApp: App {
    @NSApplicationDelegateAdaptor(PlumageAppDelegate.self) private var appDelegate
    @State private var recentProjects = RecentProjects()
    @State private var migrationRequest = MigrationRequest()
    @State private var updater = UpdaterModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        Window("Welcome to Plumage", id: "welcome") {
            // Deliberately the app's only translucent window: Xcode-style
            // welcome panel, not a content surface — the Liquid Glass
            // "no materials on content" rule doesn't apply here.
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
        // Welcome presents only when no project window restores; it never
        // restores itself — launch surface, not persistent state.
        .restorationBehavior(.disabled)
        .keyboardShortcut("0", modifiers: [.command, .shift])
        .commands {
            ProjectFileCommands(recentProjects: recentProjects, migrationRequest: migrationRequest)
            UpdateCommands(updater: updater)
        }
        .environment(recentProjects)
        .environment(migrationRequest)

        // `.commandsRemoved()` suppresses the auto "New Project" Window-menu
        // item; File > New (ProjectFileCommands) is the intended entry point.
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

        // App-global, like Settings — opens with no project window required. A
        // singleton `Window` auto-adds its Window-menu item; the scene-level
        // shortcut binds ⇧⌘T to it and (unlike a CommandGroup button) fires
        // regardless of which window is key, mirroring Welcome's ⇧⌘0.
        Window("Template Manager", id: "template-manager") {
            TemplateManagerWindowView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 680)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .keyboardShortcut("t", modifiers: [.command, .shift])

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
            ProjectFileCommands(recentProjects: recentProjects, migrationRequest: migrationRequest)
            NewIssueCommand()
            SpecEditorCommands()
            GitCommand()
            TerminalCommand()
        }
        // Restoration intentionally on: project windows open at quit
        // reopen; Welcome appears only when nothing restores.
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A write to a dead claude stdin raises SIGPIPE, whose default action
        // kills the whole app. Ignoring it surfaces the failure as a thrown
        // EPIPE from FileHandle.write, which the send paths already handle.
        signal(SIGPIPE, SIG_IGN)
        // Set the stored appearance before any window is presented; deferring to
        // applicationDidFinishLaunching flashes the system appearance first.
        AppearanceApplier.applyStored()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let coordinator = QuitCoordinator.shared
        guard !coordinator.isEmpty else { return .terminateNow }
        Task { @MainActor in
            await coordinator.runAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        // One-time, idempotent store migrations, in order: first move flat layer
        // overrides to the folder-per-layer layout so saved layer edits keep
        // applying, then rewrite legacy open-only layer blocks to the closed-marker
        // format so they still fill placeholders, then move user-authored
        // component skills into scope ownership. All pure file I/O, in sequence.
        Task.detached(priority: .utility) {
            TemplateOverrideMigration.migrateStandard()
            TemplateLayerFormatMigration.migrateStandard()
            LooseFileScopeMigration.migrateStandard()
        }
    }
}
