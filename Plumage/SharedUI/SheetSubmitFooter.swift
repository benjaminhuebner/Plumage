import SwiftUI

// Owns the single-flight submit task so Cancel and sheet
// dismissal reliably cancel an in-flight submit.
struct SheetSubmitFooter: View {
    let submitTitle: String
    let isWorking: Bool
    let canSubmit: Bool
    let onSubmit: () async -> Void
    let onDismiss: () -> Void
    @State private var submitTask: Task<Void, Never>?

    var body: some View {
        HStack {
            if isWorking {
                ProgressView().controlSize(.small)
                Text("Working…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                submitTask?.cancel()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(submitTitle) {
                guard submitTask == nil else { return }
                submitTask = Task {
                    await onSubmit()
                    submitTask = nil
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .onDisappear { submitTask?.cancel() }
    }
}
