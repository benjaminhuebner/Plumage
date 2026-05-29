import SwiftUI

// Step 3 — Git options. The three inclusion toggles only matter when a repo is
// created; they disable when the repo toggle is off. The booleans are passed
// straight through to the engine's `GitSetup` (the engine writes `.git/info/exclude`
// for anything excluded).
struct GitStepView: View {
    @Bindable var model: NewProjectModel

    var body: some View {
        Form {
            Section {
                Toggle("Create a Git repository", isOn: $model.createGitRepo)
            }
            Section {
                Toggle("Include Plumage files in the repository", isOn: $model.plumageInGit)
                Toggle("Include Claude files in the repository", isOn: $model.claudeInGit)
                Toggle("Create a .gitignore", isOn: $model.createGitignore)
            } footer: {
                Text("Excluded files stay on disk but are kept out of the repository.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!model.createGitRepo)
        }
        .formStyle(.grouped)
    }
}
