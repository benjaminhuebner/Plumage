import SwiftUI

// Container for the 4-step New Project wizard. Presented as a sheet from the
// Welcome window. Step content and the Back/Next/Create chrome are filled in by
// later tasks; this shell only proves the sheet presents and dismisses.
struct NewProjectSheet: View {
    @State private var model = NewProjectModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("New Project")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            VStack {
                Spacer()
                Text("Wizard steps coming next.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 440, idealHeight: 480)
    }
}
