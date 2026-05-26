import SwiftUI

struct ProjectSettingsView: View {
    let projectURL: URL

    @State private var model: ProjectSettingsModel

    init(projectURL: URL) {
        self.projectURL = projectURL
        _model = State(initialValue: ProjectSettingsModel(projectURL: projectURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                workflowCommandsSection
                modelsSection
                Spacer(minLength: 32)
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if case .failed(let message) = model.saveStatus {
                saveErrorBanner(message: message)
            }
        }
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
                "Plumage-Konfiguration für dieses Projekt. Änderungen werden in `Plumage.plumage/config.json` gespeichert."
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
                Text("Speichere…")
            }
            .foregroundStyle(.secondary)
            .font(.caption)
        case .saved:
            Label("Gespeichert", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .idle, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var workflowCommandsSection: some View {
        sectionHeader(
            title: "Workflow Commands",
            description:
                "Custom Slash-Commands für die drei Workflow-Buttons. Platzhalter `<slug>`, `<prompt>`, `<spec>` werden beim Run substituiert."
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
                Button("Auf Default zurücksetzen") {
                    model.resetCommand(for: action)
                }
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
    private var modelsSection: some View {
        sectionHeader(
            title: "Models",
            description: "Modell-Auswahl pro Session-Typ."
        )
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ModelSlot.allCases, id: \.self) { slot in
                ModelPickerRow(
                    label: slot.label,
                    choice: modelBinding(for: slot)
                )
            }
            Label(
                "Änderung wirkt erst auf neue Sessions/Tabs.",
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
                Text("Speichern fehlgeschlagen")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
    }

    private var bindings: ProjectSettingsBindings {
        ProjectSettingsBindings(model: model)
    }

    private func modelBinding(for slot: ModelSlot) -> Binding<ModelChoice> {
        Binding(
            get: { model.model(for: slot) },
            set: { model.setModel($0, for: slot) }
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
