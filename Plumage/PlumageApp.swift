import AppKit
import SwiftUI

@main
struct PlumageApp: App {
    @NSApplicationDelegateAdaptor(PlumageAppDelegate.self) private var appDelegate
    @State private var recentProjects = RecentProjects()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        Window("Welcome", id: "welcome") {
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
        .environment(recentProjects)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenProjectMenuButton(recentProjects: recentProjects)
            }
        }

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
        .commands {
            NewIssueCommand()
            SpecEditorCommands()
        }
        .restorationBehavior(.disabled)
        .environment(recentProjects)
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
}
