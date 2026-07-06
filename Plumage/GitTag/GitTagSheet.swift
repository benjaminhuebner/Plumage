import SwiftUI

struct GitTagSheet: View {
    @Bindable var model: GitTagModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Tag").font(.headline)

            Form {
                TextField("Name", text: $model.name)
                TextField(
                    "Message", text: $model.message,
                    prompt: Text("Optional — annotated when set"))
            }
            .formStyle(.grouped)
            .disabled(model.isWorking)

            GroupBox("Existing Tags") {
                if model.existingTags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(model.existingTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.callout.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            if let hint = model.validationHint {
                Label(hint, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            SheetSubmitFooter(
                submitTitle: "Create",
                isWorking: model.isWorking,
                canSubmit: model.canSubmit,
                onSubmit: { await model.submit() },
                onDismiss: onDismiss
            )
        }
        .padding(20)
        .frame(width: 460)
        .task { await model.load() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { onDismiss() }
        }
    }
}

#Preview {
    GitTagSheet(
        model: GitTagModel(repoURL: URL(fileURLWithPath: "/tmp/demo-repo")),
        onDismiss: {})
}
