import SwiftUI

// Second Settings tab: lets the user edit the bundled scaffold assets that
// Plumage writes into every new and migrated project, toggle which hooks/skills/
// agents get scaffolded, and author agents — all persisted to a per-user override
// store so edits survive app updates. The catalog, selection, override read/write
// and live preview are owned by `TemplatesSettingsModel`.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()

    var body: some View {
        Text("Templates")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
