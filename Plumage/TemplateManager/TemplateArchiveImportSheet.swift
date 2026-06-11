import SwiftUI

struct TemplateArchiveImportSheet: View {
    @Bindable var model: TemplateManagerModel
    let items: [TemplateArchiveItem]

    private var hasSelectedConflict: Bool {
        items.contains { $0.conflict && model.pendingImportSelection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Templates").font(.headline)
            Text(
                hasSelectedConflict
                    ? "Items marked with a warning overwrite local changes when imported."
                    : "Choose what to import."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            itemList

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelImport() }
                Button("Import") { model.confirmImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.pendingImportSelection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Toggle(isOn: selectionBinding(item.id)) {
                            Label(Self.label(for: item), systemImage: Self.icon(for: item.kind))
                        }
                        .toggleStyle(.checkbox)
                        if item.conflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help("Importing this item overwrites local changes.")
                                .accessibilityLabel("Overwrites local changes")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .frame(height: 200)
    }

    static func label(for item: TemplateArchiveItem) -> String {
        if case .deletedDefaults(let count) = item.kind {
            return "Deleted default items (\(count))"
        }
        return item.name
    }

    static func icon(for kind: TemplateArchiveItem.Kind) -> String {
        switch kind {
        case .base: return "square.grid.2x2"
        case .template: return "doc"
        case .sharedComponent: return "puzzlepiece"
        case .deletedDefaults: return "trash"
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.pendingImportSelection.contains(id) },
            set: { isOn in
                if isOn {
                    model.pendingImportSelection.insert(id)
                } else {
                    model.pendingImportSelection.remove(id)
                }
            }
        )
    }
}
