import SwiftUI

// Name prompt for authoring a new file/folder of a given kind under Base. The
// caller writes the file; this sheet only collects (and lightly validates) a name.
// Stays open if the add fails so the user can correct the name rather than losing it.
struct TemplateAddSheet: View {
    let kind: UserTemplateKind
    let onAdd: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New \(kind.addNoun)")
                .font(.headline)
            TextField("\(kind.addNoun) name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    if onAdd(name) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
