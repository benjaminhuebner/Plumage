import AppKit
import SwiftUI

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
                ErrorBanner(message: errorMessage)
            }

            Divider()

            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
        // Load the persisted catalog (custom templates, enabled flags) into the grid.
        // Re-runs on reopen since the single-instance window's view reappears.
        .task { await model.loadCatalog() }
        // Reset on close: the single-instance Window keeps its @State across
        // close/reopen. Welcome is never reopened here — it appears only at
        // launch or via the Window menu.
        .onDisappear(perform: resetState)
        .onChange(of: model.createdProject) { _, created in
            guard let created else { return }
            OpenProjectCommand.openConfirmed(
                url: created.root,
                recentProjects: recentProjects,
                openWindow: openWindow,
                dismissWindow: dismissWindow
            )
            dismiss()
        }
    }

    private func resetState() {
        model = NewProjectModel()
    }

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
        // Directory cleanup on failure is the engine's responsibility; the
        // success path continues in .onChange(of: model.createdProject).
        Task {
            await model.create(at: projectDirectory)
        }
    }
}
