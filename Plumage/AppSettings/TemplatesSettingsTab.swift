import SwiftUI

// Second Settings tab: lets the user edit the bundled scaffold assets that
// Plumage writes into every new and migrated project, toggle which hooks/skills/
// agents get scaffolded, and author agents — all persisted to a per-user override
// store so edits survive app updates. The catalog, selection, override read/write
// and live preview are owned by `TemplatesSettingsModel`.
struct TemplatesSettingsTab: View {
    @State private var model = TemplatesSettingsModel()
    @State private var addCategory: TemplatesSettingsModel.Category?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                catalogList
                Divider()
                Button {
                    openWindow(id: "template-manager")
                } label: {
                    Label("Open Template Manager…", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(8)
            }
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
        .sheet(item: $addCategory) { category in
            AddTemplateSheet(category: category) { name, wiring in
                model.addTemplate(category: category, name: name, wiring: wiring)
            }
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
                    if group.category.isAddable {
                        addRow(group.category)
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
                addRow(.agents)
            }
        }
    }

    private func addRow(_ category: TemplatesSettingsModel.Category) -> some View {
        Button {
            addCategory = category
        } label: {
            Label("Add \(category.addNoun)…", systemImage: "plus")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
                    fallbackURL: model.editingFallbackURL,
                    onSave: { model.notifySaved(relativePath: entry.relativePath) },
                    onDirtyChange: { model.setEditorDirty($0) },
                    resetToken: model.editorResetToken,
                    onResetComplete: { model.finishReset() }
                )
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
            if entry.userAuthored {
                // A user skill is listed per file but deletes as a whole tree, so the
                // Delete button appears only on its representative SKILL.md row.
                if model.canDelete(entry) {
                    Button("Delete", role: .destructive) {
                        model.delete(entry)
                    }
                }
            } else if model.isOverridden(entry) || model.isEditorDirty {
                // Reset appears the moment the bundled template is edited (dirty),
                // not only after a save has created an override on disk.
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

// Kind-aware "Add …" sheet. Name-only for docs, scripts, skills and agents; the
// hooks case adds an event picker and matcher field.
private struct AddTemplateSheet: View {
    let category: TemplatesSettingsModel.Category
    // Bool so the sheet can stay open on failure rather than dismiss with nothing created.
    let onAdd: (String, (event: HookEvent, matcher: String?)?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var event: HookEvent = .preToolUse
    @State private var matcher = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // The trigger for a new hook, or nil for kinds that have no wiring.
    private var wiring: (event: HookEvent, matcher: String?)? {
        guard category == .hooks else { return nil }
        let trimmed = matcher.trimmingCharacters(in: .whitespacesAndNewlines)
        return (event, trimmed.isEmpty ? nil : trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New \(category.addNoun)")
                .font(.headline)
            TextField("\(category.addNoun) name", text: $name)
                .textFieldStyle(.roundedBorder)
            if category == .hooks {
                Picker("Event", selection: $event) {
                    ForEach(HookEvent.allCases, id: \.self) { event in
                        Text(event.displayName).tag(event)
                    }
                }
                if event.supportsMatcher {
                    TextField("Matcher (e.g. Edit|Write)", text: $matcher)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    if onAdd(name, wiring) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var hint: String {
        switch category {
        case .agents:
            return "Creates a .claude/agents/<name>.md file written into every new project."
        case .docs:
            return "Creates a .claude/docs/<name>.md file written into every new project."
        case .plumageScripts:
            return "Creates a .plumage/scripts/<name> file written into every new project."
        case .skills:
            return "Creates a .claude/skills/<name>/SKILL.md written into every new project."
        case .hooks:
            return "Creates a .claude/hooks/<name>.sh and wires it into settings.json."
        default:
            return ""
        }
    }
}
