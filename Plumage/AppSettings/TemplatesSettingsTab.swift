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
        Form {
            ForEach(model.groupedTemplates, id: \.category.id) { group in
                Section(group.category.name) {
                    ForEach(group.templates) { template in
                        Toggle(
                            isOn: Binding(
                                get: { model.isEnabled(template) },
                                set: { model.setEnabled(template.id, $0) })
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
            Section {
                Button {
                    openWindow(id: "template-manager")
                } label: {
                    Label("Open Template Manager…", systemImage: "rectangle.3.group")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
        .onAppear { model.reload() }
    }
}
