import SwiftUI

// Step 2 — project options on a single page: name + tagline and the Git
// toggles. Replaces the former separate Metadata and Git steps. The name
// auto-focuses on appear and gates "Create" once it's a valid folder name
// (validation lives on the model). The three inclusion toggles only matter when
// a repo is created, so they disable when the repo toggle is off.
struct OptionsStepView: View {
    @Bindable var model: NewProjectModel
    @FocusState private var focused: Field?

    private enum Field {
        case name
        case tagline
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $model.name, prompt: Text("My Project"))
                    .focused($focused, equals: .name)
                TextField(
                    "Description", text: $model.tagline,
                    prompt: Text("One-line summary (optional)")
                )
                .focused($focused, equals: .tagline)
                if showsInvalidNameHint {
                    Text("The name can't contain “/” or be “.” or “..”.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Create a Git repository", isOn: $model.createGitRepo)
                Group {
                    Toggle("Include Plumage files in the repository", isOn: $model.plumageInGit)
                    Toggle("Include Claude files in the repository", isOn: $model.claudeInGit)
                    Toggle("Create a .gitignore", isOn: $model.createGitignore)
                }
                .disabled(!model.createGitRepo)
            } header: {
                Text("Git")
            } footer: {
                Text("Excluded files stay on disk but are kept out of the repository.")
                    .foregroundStyle(.secondary)
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
