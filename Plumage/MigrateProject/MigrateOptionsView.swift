import SwiftUI

struct MigrateOptionsView: View {
    @Bindable var model: MigrateProjectModel
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

            if model.isGitRepo {
                Section {
                    Toggle("Include Plumage files in the repository", isOn: $model.plumageInGit)
                    Toggle("Include Claude files in the repository", isOn: $model.claudeInGit)
                    Toggle("Create a .gitignore if missing", isOn: $model.createGitignore)
                } header: {
                    Text("Git")
                } footer: {
                    Text(
                        "This folder is already a Git repository. Files kept out stay on disk "
                            + "but are excluded via .git/info/exclude."
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Toggle("Create a Git repository", isOn: $model.initGit)
                    Group {
                        Toggle("Include Plumage files in the repository", isOn: $model.plumageInGit)
                        Toggle("Include Claude files in the repository", isOn: $model.claudeInGit)
                        Toggle("Create a .gitignore", isOn: $model.createGitignore)
                    }
                    .disabled(!model.initGit)
                } header: {
                    Text("Git")
                } footer: {
                    Text("Excluded files stay on disk but are kept out of the repository.")
                        .foregroundStyle(.secondary)
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
