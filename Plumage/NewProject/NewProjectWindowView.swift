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
    // Tracks whether this session ended in a created project, so the close
    // handler knows whether to bring Welcome back (cancel/close) or leave it
    // closed (success — the project window takes over).
    @State private var didCreate = false
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
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
        // Opening New Project closes Welcome (the window replaces it), so a
        // close that didn't create a project must bring Welcome back —
        // otherwise the app would be left with no window. On success Welcome
        // stays closed; the project window takes over.
        //
        // A single-instance `Window` also keeps its `@State` across close/reopen,
        // so every close must clear the model and the create flag — otherwise the
        // next session would resume this one's step, name, selection, and outcome.
        // The save panel is app-modal and doesn't remove this view, so it won't
        // trip this.
        .onDisappear(perform: handleWindowClose)
    }

    // Runs on every close (Cancel, red close button, or success). Two concerns,
    // kept in order: bring Welcome back unless this session created a project,
    // then clear the single-instance window's surviving `@State` so the next
    // session starts fresh.
    private func handleWindowClose() {
        if !didCreate { restoreWelcome() }
        resetState()
    }

    // A single-instance `Window` keeps its `@State` across close/reopen, so a
    // close that didn't create a project would otherwise leave the app with no
    // window. `openWindow` on an already-visible Welcome just surfaces it — the
    // single-instance scene never duplicates — so the cancel→reopen path is safe
    // even if Welcome was reopened by another route in the meantime.
    private func restoreWelcome() {
        openWindow(id: "welcome")
    }

    private func resetState() {
        model = NewProjectModel()
        didCreate = false
    }

    // The window title bar already reads "New Project", so the content header
    // leads with the current step instead of duplicating it.
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: stepIcon)
                .font(.system(size: 24))
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(stepHeadline)
                    .font(.title3.weight(.semibold))
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
                    .accessibilityLabel("Creating project")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Error: \(message)")
    }

    private var stepHeadline: String {
        switch model.currentStep {
        case .template: "Choose a Template"
        case .options: "Project Options"
        }
    }

    private var stepTitle: String {
        switch model.currentStep {
        case .template: "Pick a starting point for your new project."
        case .options: "Name your project and set up Git."
        }
    }

    private var stepIcon: String {
        switch model.currentStep {
        case .template: "square.grid.2x2"
        case .options: "slider.horizontal.3"
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
        // Attach the panel as a sheet on the New Project window instead of running
        // it app-modally, so the main runloop stays live while it is open. The key
        // window is this view's window — "Create" can only be pressed while it is
        // frontmost. If there is somehow no key window, fall back to no-op.
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            performCreate(at: url)
        }
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
                didCreate = true
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
