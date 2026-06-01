import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            TemplatesSettingsTab()
                .tabItem { Label("Templates", systemImage: "doc.text") }
        }
        .frame(width: 860, height: 560)
    }
}
