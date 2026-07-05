import SwiftUI

struct IssueTypesSettingsTab: View {
    @Environment(IssueTypeCatalogModel.self) private var model

    @State private var newTypeName = ""
    @State private var newTypeColor: Color = .gray
    @State private var newTypeColorTouched = false
    @State private var feedback: String?

    var body: some View {
        Form {
            Section {
                ForEach(model.catalog.definitions) { definition in
                    typeRow(definition)
                }
            } footer: {
                Text(
                    "When “Draft blocks Implement” is on, an issue of this type must be planned before it can be implemented. When off, Implement runs directly from a draft."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Default type", selection: model.defaultTypeBinding) {
                    ForEach(model.catalog.types, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .accessibilityLabel("Default type for new issues")
            } header: {
                Text("New issues")
            } footer: {
                Text("Pre-selected type when creating an issue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 8) {
                    IssueTypeColorSwatch(
                        color: $newTypeColor,
                        accessibilityLabel: "New issue type color"
                    )
                    .onChange(of: newTypeColor) { _, _ in newTypeColorTouched = true }
                    TextField("New type name", text: $newTypeName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addType)
                        .accessibilityLabel("New issue type name")
                    Button("Add") { addType() }
                        .disabled(
                            !IssueTypeCatalog.isValidName(
                                IssueTypeCatalog.normalize(newTypeName)
                            )
                        )
                }
                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Add type")
            } footer: {
                Text(
                    "Lowercase letters, digits, and inner hyphens — the name appears in spec frontmatter and `#if` workflow directives. Leave the color untouched for an automatic one."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func typeRow(_ definition: IssueTypeDefinition) -> some View {
        HStack(spacing: 12) {
            IssueTypeColorSwatch(
                color: model.colorBinding(for: definition.type),
                accessibilityLabel: "Color for type \(definition.type.rawValue)"
            )
            IssueTypePill(type: definition.type)
            Spacer(minLength: 0)
            Toggle("Draft blocks Implement", isOn: model.draftBlocksBinding(for: definition.type))
                .toggleStyle(.checkbox)
            Button {
                removeType(definition.type)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.catalog.definitions.count == 1)
            .help("Remove this type. Existing issues keep it until you change them.")
            .accessibilityLabel("Remove type \(definition.type.rawValue)")
        }
    }

    private func addType() {
        do {
            try model.add(
                name: newTypeName,
                colorHex: newTypeColorTouched ? newTypeColor.issueTypeHexString : nil
            )
            newTypeName = ""
            newTypeColor = .gray
            newTypeColorTouched = false
            feedback = nil
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func removeType(_ type: IssueType) {
        do {
            try model.remove(type)
            feedback = nil
        } catch {
            feedback = error.localizedDescription
        }
    }
}

// Model-owned bindings (per-row controls); live here, not in IssueCore, so
// the domain module stays SwiftUI-free.
extension IssueTypeCatalogModel {
    func draftBlocksBinding(for type: IssueType) -> Binding<Bool> {
        Binding(
            get: { self.catalog.draftBlocksImplement(for: type) },
            set: { self.setDraftBlocksImplement($0, for: type) }
        )
    }

    func colorBinding(for type: IssueType) -> Binding<Color> {
        Binding(
            get: { self.catalog.color(for: type) },
            set: { self.setColor($0.issueTypeHexString, for: type) }
        )
    }

    var defaultTypeBinding: Binding<IssueType> {
        Binding(
            get: { self.catalog.defaultType },
            set: { self.setDefaultType($0) }
        )
    }
}

#Preview {
    IssueTypesSettingsTab()
        .environment(IssueTypeCatalogModel(store: IssueTypeCatalogStore(fileURL: nil)))
        .frame(width: 500, height: 480)
}
