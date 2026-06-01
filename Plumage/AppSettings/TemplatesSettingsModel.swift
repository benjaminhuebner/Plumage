import Foundation

// Feature-local model for the Templates settings tab. Owns the catalog of bundled
// scaffold assets, the override read/write, the enable/disable toggles, the agents
// store and the live CLAUDE.md preview. State-as-bridge: disk I/O is funnelled
// through this @MainActor type so the view stays declarative.
//
// Editing model: `DocEditorView` loads from and saves to a single file URL, so to
// edit a bundled asset the model seeds its override slot with the bundled content
// on open and points the editor at the override URL. The ● marker tracks whether
// the override *differs* from the bundled original, so merely browsing (which seeds
// an identical copy) leaves a file as ○; the marker flips to ● only once a save
// makes the content diverge. Identical (no-op) overrides left behind by browsing
// are pruned on reload. Reset-to-default deletes the override.
@MainActor
@Observable
final class TemplatesSettingsModel {
    enum Category: String, CaseIterable, Identifiable {
        case claudeLayers
        case gitignore
        case hooks
        case skills
        case configs
        case docs
        case issueTemplate
        case plumageScripts
        case agents

        var id: String { rawValue }

        var title: String {
            switch self {
            case .claudeLayers: return "CLAUDE.md Layers"
            case .gitignore: return "Gitignore Fragments"
            case .hooks: return "Hooks"
            case .skills: return "Skills"
            case .configs: return "Configs"
            case .docs: return "Docs"
            case .issueTemplate: return "Issue Template"
            case .plumageScripts: return "Plumage Scripts"
            case .agents: return "Agents"
            }
        }

        // Path prefix in the assets tree this category owns. Order is the display order.
        var folderPrefix: String {
            switch self {
            case .claudeLayers: return "templates/"
            case .gitignore: return "templates/gitignore/"
            case .hooks: return "hooks/"
            case .skills: return "skills/"
            case .configs: return "configs/"
            case .docs: return "docs/"
            case .issueTemplate: return "issues/"
            case .plumageScripts: return "plumage/"
            case .agents: return "agents/"
            }
        }
    }

    struct CatalogEntry: Identifiable, Hashable {
        let relativePath: String
        let category: Category
        let label: String
        var id: String { relativePath }
    }

    let overrides: ScaffoldOverrides

    private(set) var entries: [CatalogEntry] = []
    var selection: CatalogEntry.ID?
    private(set) var editingFileURL: URL?
    // Observed mirror of which assets have an override on disk, so the ● markers
    // react to seed/save/reset without polling the filesystem in `body`.
    private(set) var overriddenPaths: Set<String> = []

    // Live preview of the composed CLAUDE.md for a chosen sample kind, run through
    // the same composer the scaffolder uses, on the current overrides.
    var sampleKind: ProjectKind = .macOS {
        didSet { refreshPreview() }
    }
    private(set) var previewText: String = ""

    // Subtractive enable/disable mask shared with the scaffolder/migrator. Changes
    // are persisted immediately so a later scaffold picks them up.
    private(set) var toggles: ScaffoldToggles

    init(overrides: ScaffoldOverrides = .standard()) {
        self.overrides = overrides
        self.toggles = .loadStandard()
        reload()
        refreshPreview()
    }

    // MARK: - Catalog

    func reload() {
        entries = Self.buildCatalog(overrides: overrides)
        pruneIdenticalOverrides()
        overriddenPaths = Set(entries.map(\.relativePath).filter { overrideDiffers($0) })
    }

    var groupedEntries: [(category: Category, entries: [CatalogEntry])] {
        Category.allCases.compactMap { category in
            let matching = entries.filter { $0.category == category }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    func entry(for id: CatalogEntry.ID) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    var selectedEntry: CatalogEntry? {
        selection.flatMap(entry(for:))
    }

    func isOverridden(_ entry: CatalogEntry) -> Bool {
        overriddenPaths.contains(entry.relativePath)
    }

    // MARK: - Enable / disable toggles

    // Which toggle category an entry belongs to, or nil if it is not toggleable.
    func toggleCategory(for entry: CatalogEntry) -> ScaffoldToggles.Category? {
        switch entry.category {
        case .hooks: return .hooks
        case .skills: return .skills
        case .agents: return .agents
        default: return nil
        }
    }

    // The toggle key for an entry, matching the names the scaffolder filters on:
    // a hook's base name (no `.sh`), a skill's directory name, an agent's file name.
    func toggleKey(for entry: CatalogEntry) -> String? {
        switch entry.category {
        case .hooks:
            return entry.label.hasSuffix(".sh") ? String(entry.label.dropLast(3)) : entry.label
        case .skills:
            return entry.label.split(separator: "/").first.map(String.init)
        case .agents:
            return entry.label
        default:
            return nil
        }
    }

    // Skills are toggled per directory but listed per file, so the checkbox is shown
    // only on the representative `SKILL.md` row. Hooks and agents are 1:1 with a file.
    func showsToggle(for entry: CatalogEntry) -> Bool {
        switch entry.category {
        case .hooks, .agents: return true
        case .skills: return entry.label.hasSuffix("/SKILL.md")
        default: return false
        }
    }

    func isEnabled(_ entry: CatalogEntry) -> Bool {
        guard let category = toggleCategory(for: entry), let key = toggleKey(for: entry)
        else { return true }
        return toggles.isEnabled(category, key)
    }

    func setEnabled(_ entry: CatalogEntry, _ enabled: Bool) {
        guard let category = toggleCategory(for: entry), let key = toggleKey(for: entry) else { return }
        toggles.setEnabled(category, key, enabled)
        try? toggles.saveStandard()
    }

    // MARK: - Editing

    func beginEditing(_ entry: CatalogEntry) {
        do {
            editingFileURL = try ensureOverride(for: entry)
            refreshOverrideStatus(for: entry.relativePath)
        } catch {
            editingFileURL = nil
        }
    }

    // Called after the editor saves the given file: the override may now differ
    // from bundled, so refresh its ● marker and the live preview.
    func notifySaved(relativePath: String) {
        refreshOverrideStatus(for: relativePath)
        refreshPreview()
    }

    func resetToDefault(_ entry: CatalogEntry) {
        guard let url = overrides.overrideURL(forRelative: entry.relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
        overriddenPaths.remove(entry.relativePath)
        if editingFileURL == url {
            editingFileURL = nil
            selection = nil
        }
        refreshPreview()
    }

    private func refreshOverrideStatus(for relativePath: String) {
        if overrideDiffers(relativePath) {
            overriddenPaths.insert(relativePath)
        } else {
            overriddenPaths.remove(relativePath)
        }
    }

    // An override counts as overridden only when its content diverges from the
    // bundled original. Files with no bundled baseline (user-authored agents)
    // count as overridden whenever an override file exists.
    private func overrideDiffers(_ relativePath: String) -> Bool {
        guard overrides.hasOverride(forRelative: relativePath),
            let overrideURL = overrides.overrideURL(forRelative: relativePath)
        else { return false }
        let bundled = overrides.bundledRoot.appending(path: relativePath)
        guard let bundledData = try? Data(contentsOf: bundled) else { return true }
        let overrideData = (try? Data(contentsOf: overrideURL)) ?? Data()
        return overrideData != bundledData
    }

    // Delete bundled-backed overrides whose content is byte-identical to the
    // bundled original (no-op overrides a browse session may have seeded). The
    // file currently open in the editor is left alone.
    private func pruneIdenticalOverrides() {
        let fm = FileManager.default
        for entry in entries where entry.category != .agents {
            guard let url = overrides.overrideURL(forRelative: entry.relativePath),
                url != editingFileURL,
                overrides.hasOverride(forRelative: entry.relativePath),
                !overrideDiffers(entry.relativePath)
            else { continue }
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Preview

    func refreshPreview() {
        let spec = NewProjectSpec(
            kind: sampleKind, name: "SampleProject", tagline: "A sample project",
            projectDirectory: URL(filePath: "/tmp/SampleProject"))
        do {
            previewText = try ClaudeMdComposer(overrides: overrides).compose(spec: spec).claudeMd
        } catch {
            previewText =
                "Preview unavailable — the composer could not build CLAUDE.md:\n\n"
                + error.localizedDescription
        }
    }

    // Copy the bundled content into the override slot if it isn't there yet, and
    // return the override URL the editor should bind to. Agents (no bundled
    // baseline) already exist in the store, so the copy is skipped.
    private func ensureOverride(for entry: CatalogEntry) throws -> URL {
        guard let overrideURL = overrides.overrideURL(forRelative: entry.relativePath) else {
            return overrides.url(forRelative: entry.relativePath)
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: overrideURL.path) {
            try fm.createDirectory(
                at: overrideURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bundled = overrides.bundledRoot.appending(path: entry.relativePath)
            if fm.fileExists(atPath: bundled.path) {
                try fm.copyItem(at: bundled, to: overrideURL)
            }
        }
        return overrideURL
    }

    // MARK: - Catalog construction

    private static func buildCatalog(overrides: ScaffoldOverrides) -> [CatalogEntry] {
        var result = bundledEntries(root: overrides.bundledRoot)
        // Agents have no bundled baseline: the catalog is the override store.
        for name in overrides.overrideFileNames(inRelativeDir: "agents") {
            result.append(
                CatalogEntry(
                    relativePath: "agents/\(name)", category: .agents, label: name))
        }
        return result
    }

    private static func bundledEntries(root: URL) -> [CatalogEntry] {
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return [] }

        let rootPath = root.standardizedFileURL.path + "/"
        var result: [CatalogEntry] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let rel = url.standardizedFileURL.path.replacingOccurrences(of: rootPath, with: "")
            guard let category = category(for: rel) else { continue }
            result.append(
                CatalogEntry(relativePath: rel, category: category, label: label(for: rel, category: category)))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    private static func category(for rel: String) -> Category? {
        // gitignore is a sub-prefix of templates/, so check it first.
        if rel.hasPrefix(Category.gitignore.folderPrefix) { return .gitignore }
        for category in Category.allCases where category != .gitignore && category != .agents {
            if rel.hasPrefix(category.folderPrefix) { return category }
        }
        return nil
    }

    private static func label(for rel: String, category: Category) -> String {
        String(rel.dropFirst(category.folderPrefix.count))
    }
}
