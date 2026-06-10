import SwiftUI

// Reduced Settings → Templates tab (#00070): an enable/disable list of the catalog's
// templates plus the "Open Template Manager…" button. Authoring, editing, membership
// and preview live in the Template Manager window now. A disabled template is hidden
// from the New Project and Migrate grids but stays in the Manager, where it is
// re-enabled. The enable state is owned by `TemplatesSettingsModel`.
//
// macOS idiom: a grouped `Form` with checkbox toggles (matching `GeneralSettingsTab`
// and the project's prior per-artifact toggle list) — not iOS-style switches in a
// plain List.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The template list scrolls inside the grouped Form; the Manager button is
        // pinned below so it is always visible regardless of how many templates exist
        // (no clipping, and the window size stays fixed — set by `AppSettingsView`).
        VStack(spacing: 0) {
            Form {
                ForEach(model.groupedTemplates, id: \.category.id) { group in
                    Section(group.category.name) {
                        ForEach(group.templates) { template in
                            Toggle(
                                isOn: model.enabledBinding(for: template)
                            ) {
                                Label {
                                    Text(template.name)
                                } icon: {
                                    TemplateImageView(image: template.image) {
                                        model.imageURL(forRelative: $0)
                                    }
                                    .frame(width: 16, height: 16)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            Button {
                openWindow(id: "template-manager")
            } label: {
                Label("Open Template Manager…", systemImage: "rectangle.3.group")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(12)
        }
        .onAppear { model.reload() }
    }
}
