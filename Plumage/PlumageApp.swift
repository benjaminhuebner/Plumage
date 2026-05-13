import AppKit
import Combine
import SwiftUI

@main
struct PlumageApp: App {
    @NSApplicationDelegateAdaptor(PlumageAppDelegate.self) private var appDelegate
    @State private var recentProjects = RecentProjects()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        Window("Welcome", id: "welcome") {
            WelcomeView(hiddenOnFirstShow: appDelegate.hasPendingLaunchURL)
                .containerBackground(.thickMaterial, for: .window)
                .task {
                    await recentProjects.load()
                    appDelegate.attachHandler(handleOpenURL)
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
                    .task { appDelegate.attachHandler(handleOpenURL) }
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

    private func handleOpenURL(_ url: URL) {
        OpenProjectCommand.openFromBundleURL(
            url,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
    }
}

@MainActor
final class PlumageAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var hasPendingLaunchURL = false
    private var pendingURLs: [URL] = []
    private var handler: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler {
            urls.forEach(handler)
            return
        }
        pendingURLs.append(contentsOf: urls)
        hasPendingLaunchURL = true
    }

    func attachHandler(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        guard !pendingURLs.isEmpty else { return }
        let pending = pendingURLs
        pendingURLs = []
        hasPendingLaunchURL = false
        pending.forEach(handler)
    }
}
