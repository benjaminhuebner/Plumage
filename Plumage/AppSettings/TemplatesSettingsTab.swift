import SwiftUI

// Second Settings tab: lets the user edit the bundled scaffold assets that
// Plumage writes into every new and migrated project, toggle which hooks/skills/
// agents get scaffolded, and author agents — all persisted to a per-user override
// store so edits survive app updates. The catalog, selection, override read/write
// and live preview are owned by `TemplatesSettingsModel`.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()
    @State private var showAddAgent = false
    @State private var newAgentName = ""

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            catalogList
                .frame(width: 240)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            previewPane
                .frame(width: 320)
        }
        // Resizable with a floor: this tab hosts a code editor plus catalog and
        // preview columns, so the user benefits from enlarging it — unlike the
        // compact, fixed General tab.
        .frame(
            minWidth: 880, idealWidth: 1040, maxWidth: .infinity,
            minHeight: 520, idealHeight: 600, maxHeight: .infinity
        )
        .onAppear { model.reload() }
        .onChange(of: model.selection) { _, _ in
            if let entry = model.selectedEntry {
                model.beginEditing(entry)
            }
        }
        .alert("New Agent", isPresented: $showAddAgent) {
            TextField("Agent name", text: $newAgentName)
            Button("Add") {
                model.addAgent(name: newAgentName)
                newAgentName = ""
            }
            Button("Cancel", role: .cancel) { newAgentName = "" }
        } message: {
            Text("Creates a .claude/agents/<name>.md file written into every new project.")
        }
    }

    // MARK: - Catalog

    private var catalogList: some View {
        @Bindable var model = model
        return List(selection: $model.selection) {
            ForEach(model.groupedEntries.filter { $0.category != .agents }, id: \.category.id) { group in
                Section(group.category.title) {
                    ForEach(group.entries) { entry in
                        catalogRow(entry)
                            .tag(entry.id)
                    }
                }
            }
            // Agents are user-authored and always shown so the add affordance is
            // reachable even when none exist yet.
            Section(TemplatesSettingsModel.Category.agents.title) {
                ForEach(model.agentEntries) { entry in
                    catalogRow(entry)
                        .tag(entry.id)
                }
                Button {
                    showAddAgent = true
                } label: {
                    Label("Add Agent…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func catalogRow(_ entry: TemplatesSettingsModel.CatalogEntry) -> some View {
        HStack(spacing: 6) {
            if model.showsToggle(for: entry) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.isEnabled(entry) },
                        set: { model.setEnabled(entry, $0) })
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            Image(systemName: model.isOverridden(entry) ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(model.isOverridden(entry) ? Color.accentColor : .secondary)
            Text(entry.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(model.isEnabled(entry) ? .primary : .secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var detail: some View {
        if let url = model.editingFileURL, let entry = model.selectedEntry {
            VStack(spacing: 0) {
                detailHeader(entry)
                Divider()
                DocEditorView(
                    fileURL: url, displayName: entry.label,
                    fallbackURL: model.editingFallbackURL
                ) {
                    model.notifySaved(relativePath: entry.relativePath)
                }
                .id(url)
            }
        } else {
            ContentUnavailableView(
                "Select a Template",
                systemImage: "doc.text",
                description: Text("Edit any bundled asset; your copy is used for every new project."))
        }
    }

    private func detailHeader(_ entry: TemplatesSettingsModel.CatalogEntry) -> some View {
        HStack {
            Text(entry.label)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if entry.category == .agents {
                Button("Delete", role: .destructive) {
                    model.deleteAgent(entry)
                }
            } else if model.isOverridden(entry) {
                Button("Reset to Default") {
                    model.resetToDefault(entry)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Preview

    private var previewPane: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Text("CLAUDE.md Preview")
                    .font(.headline)
                Spacer()
                Picker("", selection: $model.sampleKind) {
                    ForEach(ProjectKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                Text(model.previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }
}
