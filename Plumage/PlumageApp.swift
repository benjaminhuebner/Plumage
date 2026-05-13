import SwiftUI

@main
struct PlumageApp: App {
    @State private var recentProjects = RecentProjects()

    var body: some Scene {
        Window("Welcome", id: "welcome") {
            WelcomeView()
                .containerBackground(.thickMaterial, for: .window)
                .task { await recentProjects.load() }
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
}
