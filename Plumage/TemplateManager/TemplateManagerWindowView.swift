import SwiftUI

// Read-only, app-global window for browsing the template catalog. The three-column
// shell is built up across the Phase C tasks; this is the scene entry point.
struct TemplateManagerWindowView: View {
    var body: some View {
        Text("Template Manager")
            .frame(minWidth: 820, minHeight: 520)
    }
}
