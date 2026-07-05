import SwiftUI

struct AppSettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        // Each pane fits its own content (native macOS tabbed-prefs behavior).
        // Width stays constant so tab switches resize vertically only; fixed
        // heights — not min/ideal — keep dense tabs from ballooning the window.
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsTab()
                .frame(width: Self.paneWidth, height: 260)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            IssueTypesSettingsTab()
                .frame(width: Self.paneWidth, height: 560)
                .tabItem { Label("Issue Types", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.issueTypes)
            TemplatesSettingsTab()
                .frame(width: Self.paneWidth, height: 452)
                .tabItem { Label("Templates", systemImage: "doc.text") }
                .tag(SettingsTab.templates)
            UsageSettingsTab()
                .frame(width: Self.paneWidth, height: 240)
                .tabItem { Label("Usage", systemImage: "gauge.medium") }
                .tag(SettingsTab.usage)
            AccountsSettingsTab()
                .frame(width: Self.paneWidth, height: 408)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
        }
    }

    private static let paneWidth: CGFloat = 500
}
