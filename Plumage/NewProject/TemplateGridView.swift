import SwiftUI

// Shared template picker grid for the New Project and Migrate Project flows. Reads
// the resolved catalog: sections are categories (in catalog order), tiles are the
// category's enabled templates rendered with their `TemplateImage` (SF Symbol or
// imported file). Selection is the chosen template's id. A category whose templates
// are all disabled is hidden; when every template is disabled the grid shows a hint
// pointing at the Template Manager rather than an empty surface.
struct TemplateGridView: View {
    let catalog: TemplateCatalog
    @Binding var selectedTemplateID: String?
    let resolveImage: (String) -> URL?

    @Environment(\.openWindow) private var openWindow

    private static let columns = [GridItem(.adaptive(minimum: 116), spacing: 12)]

    private var visibleCategories: [(category: TemplateCategory, templates: [TemplateDescriptor])] {
        catalog.sortedCategories.compactMap { category in
            let templates = catalog.enabledTemplates(inCategory: category.id)
            return templates.isEmpty ? nil : (category, templates)
        }
    }

    var body: some View {
        if visibleCategories.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(visibleCategories, id: \.category.id) { entry in
                    Section {
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 12) {
                            ForEach(entry.templates) { template in
                                tile(for: template)
                            }
                        }
                    } header: {
                        Text(entry.category.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No templates are enabled.")
                .font(.headline)
            Text("Enable a template in Settings, or add one in the Template Manager.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                openWindow(id: "template-manager")
            } label: {
                Label("Open Template Manager…", systemImage: "rectangle.3.group")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func tile(for template: TemplateDescriptor) -> some View {
        let isSelected = selectedTemplateID == template.id
        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(spacing: 8) {
                TemplateImageView(image: template.image, resolve: resolveImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    )
                Text(template.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
