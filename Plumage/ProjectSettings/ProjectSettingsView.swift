import SwiftUI

struct ProjectSettingsView: View {
    let projectURL: URL

    @State private var model: ProjectSettingsModel
    @State private var showRenameConfirm = false
    @Environment(\.onProjectConfigSaved) private var onProjectConfigSaved

    init(projectURL: URL) {
        self.projectURL = projectURL
        _model = State(initialValue: ProjectSettingsModel(projectURL: projectURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                switch model.loadState {
                case .loading:
                    loadingPlaceholder
                case .failed(let message):
                    loadFailedBanner(message: message)
                case .loaded:
                    projectSection
                    workflowCommandsSection
                    workflowModesSection
                    modelsSection
                }
                Spacer(minLength: 32)
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            model.onSaved = onProjectConfigSaved
            await model.load()
        }
        .onDisappear {
            // Belt-and-braces: a typed-into command text within the 500ms
            // debounce window survives navigating away from settings. Picker
            // selections already saveNow synchronously in the model.
            Task { [model] in await model.saveNow() }
        }
        .overlay(alignment: .bottom) {
            if case .failed(let message) = model.saveStatus {
                saveErrorBanner(message: message)
            }
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading project settings…")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func loadFailedBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Could not load project settings")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Project Settings")
                    .font(.title)
                    .bold()
                saveStatusBadge
                Spacer(minLength: 0)
            }
            Text(
                "Plumage configuration for this project. Changes are saved to `Plumage.plumage/config.json`."
            )
            .foregroundStyle(.secondary)
            .font(.callout)
        }
    }

    @ViewBuilder
    private var saveStatusBadge: some View {
        switch model.saveStatus {
        case .saving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Saving…")
            }
            .foregroundStyle(.secondary)
            .font(.caption)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .idle, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        sectionHeader(
            title: "Project",
            description:
                "The project's display name. Renaming also renames the `.plumage` bundle folder on disk; the project folder itself is left alone."
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Project name", text: projectNameBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit {
                        if model.canRename { showRenameConfirm = true }
                    }
                Button("Rename…") { showRenameConfirm = true }
                    .disabled(!model.canRename)
                if model.renameStatus == .renaming {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            if case .failed(let message) = model.renameStatus {
                renameErrorBanner(message: message)
            }
        }
        .confirmationDialog(
            "Rename this project?",
            isPresented: $showRenameConfirm,
            titleVisibility: .visible
        ) {
            Button("Rename") { Task { await model.rename() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Renames the bundle on disk to “\(model.trimmedProjectName).plumage” and updates the window title. A running chat session keeps going."
            )
        }
    }

    @ViewBuilder
    private func renameErrorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rename failed")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.dismissRenameError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var workflowCommandsSection: some View {
        sectionHeader(
            title: "Workflow Commands",
            description:
                "Custom slash-commands for the three workflow buttons. The placeholders `<slug>`, `<prompt>`, `<spec>` are substituted at run time. An empty prompt.md substitutes to an empty string."
        )
        VStack(alignment: .leading, spacing: 18) {
            workflowEditor(for: .plan, binding: bindings.planCommand)
            workflowEditor(for: .implement, binding: bindings.implementCommand)
            workflowEditor(for: .review, binding: bindings.reviewCommand)
        }
    }

    @ViewBuilder
    private func workflowEditor(
        for action: WorkflowAction,
        binding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.label)
                    .font(.headline)
                Spacer()
                Button("Reset command") {
                    model.resetCommand(for: action)
                }
                .help("Resets the command text only. Permission mode is in the Workflow Modes section below.")
                .controlSize(.small)
            }
            WorkflowCommandEditor(
                text: binding,
                onPlaceholderInsert: { placeholder in
                    insertPlaceholder(placeholder, into: binding)
                }
            )
            .frame(minHeight: 90)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 6) {
                ForEach(WorkflowPlaceholder.allCases, id: \.self) { placeholder in
                    Button {
                        insertPlaceholder(placeholder, into: binding)
                    } label: {
                        Text(placeholder.token)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var workflowModesSection: some View {
        sectionHeader(
            title: "Workflow Modes",
            description:
                "Permission mode passed to claude for each workflow button. Each action's default is pre-selected — pick another to override it."
        )
        VStack(alignment: .leading, spacing: 8) {
            ForEach(WorkflowAction.allCases, id: \.self) { action in
                WorkflowModePickerRow(
                    label: action.settingsLabel,
                    mode: permissionModeBinding(for: action),
                    fallback: model.resolvedFallbackMode(for: action)
                )
            }
            Label(
                "Changes only apply to new sessions and tabs.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        sectionHeader(
            title: "Models",
            description: "Model selection per session type."
        )
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ModelSlot.allCases, id: \.self) { slot in
                ModelPickerRow(
                    label: slot.label,
                    choice: modelBinding(for: slot),
                    fallback: ModelsConfig.slotDefault(for: slot)
                )
            }
            Label(
                "Changes only apply to new sessions and tabs.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3)
                .bold()
            Text(description)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func saveErrorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save failed")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { Task { await model.saveNow() } }
                .controlSize(.small)
            Button {
                model.dismissSaveError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
    }

    private var bindings: ProjectSettingsBindings {
        ProjectSettingsBindings(model: model)
    }

    private var projectNameBinding: Binding<String> {
        Binding(
            get: { model.projectName },
            set: { model.projectName = $0 }
        )
    }

    private func modelBinding(for slot: ModelSlot) -> Binding<ModelChoice> {
        Binding(
            get: { model.model(for: slot) },
            set: { model.setModel($0, for: slot) }
        )
    }

    private func permissionModeBinding(for action: WorkflowAction) -> Binding<PermissionMode?> {
        Binding(
            get: { model.permissionMode(for: action) },
            set: { model.setPermissionMode($0, for: action) }
        )
    }

    private func insertPlaceholder(_ placeholder: WorkflowPlaceholder, into binding: Binding<String>) {
        let current = binding.wrappedValue
        let suffix = current.hasSuffix(" ") || current.isEmpty ? "" : " "
        binding.wrappedValue = current + suffix + placeholder.token
    }
}

// Compact binding object so the view body stays terse — every editable
// command field funnels through ProjectSettingsModel.setCommand which
// schedules the debounced disk write.
@MainActor
private struct ProjectSettingsBindings {
    let model: ProjectSettingsModel

    var planCommand: Binding<String> {
        Binding(
            get: { model.planCommand },
            set: { model.setCommand($0, for: .plan) }
        )
    }
    var implementCommand: Binding<String> {
        Binding(
            get: { model.implementCommand },
            set: { model.setCommand($0, for: .implement) }
        )
    }
    var reviewCommand: Binding<String> {
        Binding(
            get: { model.reviewCommand },
            set: { model.setCommand($0, for: .review) }
        )
    }
}

nonisolated enum WorkflowPlaceholder: String, CaseIterable, Sendable, Hashable {
    case slug
    case prompt
    case spec

    var token: String { "<\(rawValue)>" }
}
