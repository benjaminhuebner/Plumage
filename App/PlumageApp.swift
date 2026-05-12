import SwiftUI

@main
struct PlumageApp: App {
    @State private var recentProjects = RecentProjects()

    var body: some Scene {
        Window("Welcome", id: "welcome") {
            WelcomeView()
        }
        .defaultLaunchBehavior(.presented)
        .environment(recentProjects)

        WindowGroup("Project", for: ProjectHandle.self) { $handle in
            if let handle {
                Text("Project (placeholder) \(handle.url.path)")
                    .frame(minWidth: 640, minHeight: 480)
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
