import SwiftUI

struct MigrateProjectWindowView: View {
    @Environment(MigrationRequest.self) private var request
    @Environment(\.openWindow) private var openWindow
    @State private var model: MigrateProjectModel?

    var body: some View {
        Group {
            if let model {
                MigrateProjectFlowView(model: model)
                    .id(request.generation)
            } else {
                ProgressView("Inspecting folder…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
        // The single-instance window keeps `@State` across reopen; rebuild the
        // model on every present (keyed on `generation`, not the URL, so
        // re-migrating the same folder still starts a fresh flow) and detect.
        .task(id: request.generation) {
            guard let url = request.folderURL else { return }
            model = MigrateProjectModel(folderURL: url)
            await model?.load()
        }
        // Opening Migrate closed Welcome, so a close that didn't open a project
        // must bring Welcome back or the app is left with no window. Must live on
        // the window root, not the `generation`-keyed flow view: a re-present
        // swaps the flow view's identity (firing *its* onDisappear) while the
        // window stays open — only the root disappears on a real close.
        .onDisappear {
            if model?.didOpenProject != true { openWindow(id: "welcome") }
        }
    }
}

private struct MigrateProjectFlowView: View {
    @Bindable var model: MigrateProjectModel
    @State private var migrateTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(RecentProjects.self) private var recentProjects
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let report = model.report {
                reportView(report)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let error = model.error {
                    errorBanner(error)
                }
            }

            Divider()

            footer
        }
        // A re-present swaps this view's identity; cancel any in-flight migration
        // so it can't write back into the model being torn down. Welcome-reopen
        // lives on the window root (see there), not here.
        .onDisappear {
            migrateTask?.cancel()
        }
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
                Text(stepSubtitle)
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
        case .template:
            TemplateGridView(
                catalog: model.catalog,
                selectedTemplateID: $model.selectedTemplateID,
                resolveImage: { model.imageURL(forRelative: $0) })
        case .options: MigrateOptionsView(model: model)
        }
    }

    private var footer: some View {
        HStack {
            if model.report == nil {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isMigrating)

                Spacer()

                if model.isMigrating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Migrating project")
                }

                if !model.isFirstStep {
                    Button("Back") { model.goBack() }
                        .disabled(model.isMigrating)
                }

                if model.isLastStep {
                    Button("Migrate", action: performMigrate)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canMigrate)
                } else {
                    Button("Next") { model.advance() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canAdvance)
                }
            } else {
                Spacer()
                Button("Open Project", action: openMigrated)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func reportView(_ report: MigrationReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Migration complete", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                if !report.added.isEmpty {
                    reportSection(title: "Added", items: report.added, systemImage: "plus.circle")
                }
                if !report.skipped.isEmpty {
                    reportSection(
                        title: "Kept (already present)", items: report.skipped,
                        systemImage: "checkmark.circle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func reportSection(title: String, items: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(items.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
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
        if model.report != nil { return "Migration Complete" }
        switch model.currentStep {
        case .template: return "Choose a Template"
        case .options: return "Project Options"
        }
    }

    private var stepSubtitle: String {
        if model.report != nil { return model.folderURL.lastPathComponent }
        switch model.currentStep {
        case .template: return "Confirm the detected type or pick another."
        case .options: return "Name your project and set up Git."
        }
    }

    private var stepIcon: String {
        if model.report != nil { return "checkmark.seal" }
        switch model.currentStep {
        case .template: return "square.grid.2x2"
        case .options: return "slider.horizontal.3"
        }
    }

    private func performMigrate() {
        migrateTask = Task { [weak model] in await model?.migrate() }
    }

    private func openMigrated() {
        guard let project = model.migratedProject else { return }
        model.didOpenProject = true
        OpenProjectCommand.openConfirmed(
            url: project.root,
            recentProjects: recentProjects,
            openWindow: openWindow,
            dismissWindow: dismissWindow
        )
        dismiss()
    }
}
