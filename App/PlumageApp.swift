import SwiftUI

@main
struct PlumageApp: App {
    @State private var recentProjects = RecentProjects()

    var body: some Scene {
        Window("Welcome", id: "welcome") {
            WelcomeView()
        }
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
                Text("No project")
                    .frame(minWidth: 320, minHeight: 240)
            }
        }
        .commandsRemoved()
        .restorationBehavior(.disabled)
        .environment(recentProjects)
    }
}
