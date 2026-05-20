import AppKit
import SwiftUI

struct InlineCreateRow: View {
    let projectURL: URL
    let icon: String
    @Environment(NavigatorModel.self) private var navigator
    @FocusState private var focused: Bool
    @State private var didAutoFocus = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(
                "",
                text: nameBinding,
                prompt: Text(navigator.pendingCreate?.section.defaultName ?? "")
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit {
                Task { @MainActor in
                    _ = await navigator.commitPendingCreate(projectURL: projectURL)
                }
            }
            .onExitCommand {
                navigator.cancelPendingCreate()
            }
            .onChange(of: focused) { _, isFocused in
                // Blur-commit: when the textfield loses focus without an
                // explicit submit, treat it like Enter — same rule as Finder
                // inline rename. Empty input is still a no-op.
                guard didAutoFocus, !isFocused else { return }
                Task { @MainActor in
                    _ = await navigator.commitPendingCreate(projectURL: projectURL)
                }
            }
        }
        // Small delay so the row's TextField is part of the responder chain
        // before we ask for focus — bug surfaces as "first +-click doesn't
        // focus" without it (see notes.md).
        .task(id: navigator.pendingCreate?.id) {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
            didAutoFocus = true
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { navigator.pendingCreate?.name ?? "" },
            set: { newValue in
                guard navigator.pendingCreate != nil else { return }
                navigator.pendingCreate?.name = newValue
            }
        )
    }
}

struct SectionHeaderAddButton: View {
    let action: () -> Void
    var help: String = "Create"

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
