import AppKit
import SwiftUI

// Step 4 — pick the parent directory. The project folder is `<parent>/<name>`
// (name comes from step 2), so there's no second naming dialog. The resulting
// path is previewed and a collision blocks "Create".
struct LocationStepView: View {
    @Bindable var model: NewProjectModel

    var body: some View {
        Form {
            Section("Parent Folder") {
                HStack {
                    Text(model.parentDirectory?.path ?? "No folder chosen")
                        .foregroundStyle(model.parentDirectory == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseParent)
                }
            }

            Section("Project Folder") {
                if let projectDirectory = model.projectDirectory {
                    Text(projectDirectory.path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if model.projectDirectoryExists {
                        Label(
                            "A folder named “\(model.trimmedName)” already exists here. "
                                + "Pick another name or location.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                } else {
                    Text("Choose a parent folder to preview the project path.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Parent Folder"
        panel.message = "The project folder will be created inside the folder you pick."
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            model.parentDirectory = panel.url
        }
    }
}
