import SwiftUI

// Step 2 — project name and one-line description. The name auto-focuses on
// appear; the description is optional. "Next" enables once the name is a valid
// folder name (validation lives on the model).
struct MetadataStepView: View {
    @Bindable var model: NewProjectModel
    @FocusState private var focused: Field?

    private enum Field {
        case name
        case tagline
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $model.name, prompt: Text("My Project"))
                    .focused($focused, equals: .name)
                TextField(
                    "Description", text: $model.tagline,
                    prompt: Text("One-line summary (optional)")
                )
                .focused($focused, equals: .tagline)
            } footer: {
                if showsInvalidNameHint {
                    Text("The name can't contain “/” or be “.” or “..”.")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        // Auto-focus is dropped if assigned during the present animation frame;
        // a short hop lands it reliably (notes.md 2026-05-14 #00017).
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focused = .name
        }
    }

    private var showsInvalidNameHint: Bool {
        !model.trimmedName.isEmpty && !model.isMetadataStepValid
    }
}
