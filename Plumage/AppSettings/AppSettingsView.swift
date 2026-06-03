import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            TemplatesSettingsTab()
                .tabItem { Label("Templates", systemImage: "doc.text") }
        }
        // One stable window size for the whole Settings scene: the window must not
        // jump size when switching tabs (the per-tab frames from #00064 caused that —
        // reversed here now that Templates is a compact list, not the old editor).
        .frame(width: 480, height: 380)
    }
}
