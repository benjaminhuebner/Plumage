import SwiftUI

// Container for the 4-step New Project wizard, presented as a sheet from the
// Welcome window. Owns the wizard model, switches between step views, and drives
// Back/Next/Create navigation plus progress and error feedback. The success path
// (open the created project) is wired in `performCreate`.
struct NewProjectSheet: View {
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
        .frame(minWidth: 560, idealWidth: 600, minHeight: 470, idealHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Project")
                .font(.title2.weight(.semibold))
            Text(stepTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.currentStep {
        case .type: TypeStepView(model: model)
        case .metadata: MetadataStepView(model: model)
        case .git: GitStepView(model: model)
        case .location: LocationStepView(model: model)
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
                Button("Create", action: performCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            } else {
                Button("Next") { model.advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
            }
        }
        .padding()
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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
    }

    private var stepTitle: String {
        switch model.currentStep {
        case .type: "Choose a project type"
        case .metadata: "Name your project"
        case .git: "Set up Git"
        case .location: "Choose where to create it"
        }
    }

    private func performCreate() {
        Task {
            let result = await model.create()
            // On success the engine returns the project root; reuse the existing
            // open path (records the recent, opens the window, dismisses Welcome —
            // which tears down this sheet). On failure the model's errorMessage
            // drives the banner and the wizard stays open. Directory cleanup on
            // failure is the engine's responsibility.
            if case .success(let created) = result {
                OpenProjectCommand.openConfirmed(
                    url: created.root,
                    recentProjects: recentProjects,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            }
        }
    }
}
