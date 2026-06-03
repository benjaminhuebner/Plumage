import SwiftUI

// A validated request to author a custom shared component. The model turns it into
// a descriptor with an own starter file and the chosen template memberships.
struct NewSharedComponentRequest {
    let name: String
    let kind: SharedComponentKind
    let memberTemplateIDs: Set<String>
}

// Authoring sheet for a shared component: name + kind + a checklist of templates
// that include it. Name is required (Add stays disabled until present).
struct NewSharedComponentSheet: View {
    let catalog: TemplateCatalog
    let onAdd: (NewSharedComponentRequest) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: SharedComponentKind = .layer
    @State private var members: Set<String> = []

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Shared Component").font(.headline)

            Form {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(SharedComponentKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }
            .formStyle(.grouped)

            Text("Included in templates")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            membershipList

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    if onAdd(
                        NewSharedComponentRequest(
                            name: trimmedName, kind: kind, memberTemplateIDs: members))
                    {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var membershipList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(catalog.templates.sorted { $0.name < $1.name }) { template in
                    Toggle(
                        isOn: Binding(
                            get: { members.contains(template.id) },
                            set: { isOn in
                                if isOn { members.insert(template.id) } else { members.remove(template.id) }
                            })
                    ) {
                        Text(template.name)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .frame(height: 160)
    }
}
