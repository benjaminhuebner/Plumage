import SwiftUI

// Reduced Settings → Templates tab (#00070): an enable/disable list of the catalog's
// templates plus the "Open Template Manager…" button. Authoring, editing, membership
// and preview live in the Template Manager window now. A disabled template is hidden
// from the New Project and Migrate grids but stays in the Manager, where it is
// re-enabled. The enable state is owned by `TemplatesSettingsModel`.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.groupedTemplates, id: \.category.id) { group in
                    Section(group.category.name) {
                        ForEach(group.templates) { template in
                            row(template)
                        }
                    }
                }
            }
            Divider()
            Button {
                openWindow(id: "template-manager")
            } label: {
                Label("Open Template Manager…", systemImage: "rectangle.3.group")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(8)
        }
        .frame(
            minWidth: 440, idealWidth: 520, maxWidth: .infinity,
            minHeight: 360, idealHeight: 460, maxHeight: .infinity
        )
        .onAppear { model.reload() }
    }

    private func row(_ template: TemplateDescriptor) -> some View {
        Toggle(
            isOn: Binding(
                get: { model.isEnabled(template) },
                set: { model.setEnabled(template.id, $0) })
        ) {
            HStack(spacing: 8) {
                TemplateImageView(image: template.image) { model.imageURL(forRelative: $0) }
                    .frame(width: 18, height: 18)
                Text(template.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
