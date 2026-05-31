import AppKit
import SwiftUI

// Root of the standalone New Project window (a single-instance `Window` scene,
// not a sheet — #00060 supersedes the #00055 4-step sheet). Owns the wizard
// model, switches between the two steps (template → options), and drives
// Back/Next navigation plus progress and error feedback. "Create" opens the
// macOS standard save panel; the panel URL is the project folder. The success
// path reuses `OpenProjectCommand.openConfirmed` and then closes this window.
struct NewProjectWindowView: View {
    @State private var model = NewProjectModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(RecentProjects.self) private var recentProjects
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage = model.errorMessage {
                errorBanner(errorMessage)
            }

            Divider()

            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("New Project")
                    .font(.title2.weight(.semibold))
                Text(stepTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.currentStep {
        case .template: TypeStepView(model: model)
        case .options: OptionsStepView(model: model)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCreating)

            Spacer()

            if model.isCreating {
                ProgressView()
                    .controlSize(.small)
            }

            if !model.isFirstStep {
                Button("Back") { model.goBack() }
                    .disabled(model.isCreating)
            }

            if model.isLastStep {
                Button("Create", action: presentSavePanel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            } else {
                Button("Next") { model.advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.red)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
    }

    private var stepTitle: String {
        switch model.currentStep {
        case .template: "Choose a template for your new project"
        case .options: "Configure your project"
        }
    }

    // "Create" → macOS standard save panel. The panel URL (chosen location plus
    // the typed file name) is the project folder; cancelling leaves the options
    // page untouched. The save panel's name field is pre-filled with the project
    // name and can create directories.
    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.title = "Create New Project"
        panel.message = "Choose where to create the project folder."
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = model.trimmedName
        panel.canCreateDirectories = true
        panel.prompt = "Create"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performCreate(at: url)
    }

    private func performCreate(at projectDirectory: URL) {
        Task {
            let result = await model.create(at: projectDirectory)
            // On success the engine returns the project root; reuse the existing
            // open path (records the recent, opens the project window, dismisses
            // Welcome), then close this window. On failure the model's
            // errorMessage drives the banner and the window stays on the options
            // page. Directory cleanup on failure is the engine's responsibility.
            if case .success(let created) = result {
                OpenProjectCommand.openConfirmed(
                    url: created.root,
                    recentProjects: recentProjects,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
                dismiss()
            }
        }
    }
}
