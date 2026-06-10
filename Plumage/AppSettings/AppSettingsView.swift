import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            TemplatesSettingsTab()
                .tabItem { Label("Templates", systemImage: "doc.text") }
        }
        // One stable window size for the whole Settings scene: per-tab frames
        // made the window jump size when switching tabs — reversed now that
        // Templates is a compact list, not the old editor.
        .frame(width: 480, height: 380)
    }
}
