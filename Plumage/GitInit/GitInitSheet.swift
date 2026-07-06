import SwiftUI

struct GitInitSheet: View {
    @Bindable var model: GitInitModel
    let onDismiss: () -> Void
    var onInitialized: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Initialize Git Repository").font(.headline)

            Form {
                Section {
                    Toggle("Include Plumage files in the repository", isOn: $model.plumageInGit)
                    Toggle("Include Claude files in the repository", isOn: $model.claudeInGit)
                    Toggle("Create a .gitignore", isOn: $model.createGitignore)
                } footer: {
                    Text("Excluded files stay on disk but are kept out of the repository.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(model.isWorking)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            SheetSubmitFooter(
                submitTitle: "Initialize",
                isWorking: model.isWorking,
                canSubmit: !model.isWorking,
                onSubmit: { await model.submit() },
                onDismiss: onDismiss
            )
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: model.didFinish) { _, finished in
            if finished {
                onInitialized?()
                onDismiss()
            }
        }
    }
}

#Preview {
    GitInitSheet(
        model: GitInitModel(repoURL: URL(fileURLWithPath: "/tmp/demo"), projectName: "Demo"),
        onDismiss: {})
}
