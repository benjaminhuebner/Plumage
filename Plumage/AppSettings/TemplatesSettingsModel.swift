import Foundation

// Feature-local model for the Templates settings tab. Owns the catalog of bundled
// scaffold assets, the override read/write, the enable/disable toggles, the agents
// store and the live CLAUDE.md preview. State-as-bridge: disk I/O is funnelled
// through this @MainActor type so the view stays declarative.
//
// Editing model: the editor reads from a fallback (the bundled original) but saves
// to the override slot, so browsing an asset creates no override. Without that, a
// merely-viewed asset would pin its content and shadow future bundled updates.
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

        // Whether the user can author a new item of this kind from scratch.
        var isAddable: Bool {
            switch self {
            case .agents, .docs, .plumageScripts, .skills, .hooks: return true
            default: return false
            }
        }

        // Singular noun for the "Add …" affordance, empty for non-addable kinds.
        var addNoun: String {
            switch self {
            case .agents: return "Agent"
            case .docs: return "Doc"
            case .plumageScripts: return "Script"
            case .skills: return "Skill"
            case .hooks: return "Hook"
            default: return ""
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
        // No bundled baseline exists at `relativePath`: the entry lives only in the
        // user's override store. Drives Delete (user-authored) vs Reset (bundled).
        let userAuthored: Bool
        var id: String { relativePath }
    }

    let overrides: ScaffoldOverrides

    private(set) var entries: [CatalogEntry] = []
    var selection: CatalogEntry.ID?
    private(set) var editingFileURL: URL?
    // Read-only baseline the editor falls back to while the override slot is empty,
    // so opening an asset never writes to disk. nil for user-authored agents.
    private(set) var editingFallbackURL: URL?
    // Observed mirror of which assets have an override on disk, so the ● markers
    // react to seed/save/reset without polling the filesystem in `body`.
    private(set) var overriddenPaths: Set<String> = []

    // Live dirty state of the embedded editor, surfaced by `DocEditorView` so the
    // header can show Reset to Default on the first edit (before any save creates an
    // override). Reset on each selection change via `beginEditing`.
    private(set) var isEditorDirty = false

    func setEditorDirty(_ dirty: Bool) {
        if isEditorDirty != dirty { isEditorDirty = dirty }
    }

    // Live preview of the composed CLAUDE.md for a chosen sample kind, run through
    // the same composer the scaffolder uses, on the current overrides.
    var sampleKind: ProjectKind = .macOS {
        didSet { refreshPreview() }
    }
    private(set) var previewText: String = ""

    // Subtractive enable/disable mask shared with the scaffolder/migrator. Changes
    // are persisted immediately so a later scaffold picks them up.
    private(set) var toggles: ScaffoldToggles

    // Trigger metadata for user-authored hooks, persisted alongside the toggles so a
    // later scaffold wires them into `settings.json`. Injectable for hermetic tests.
    private let hookWiringStoreURL: URL?
    private var hookWirings: HookWiringStore

    init(overrides: ScaffoldOverrides = .standard(), hookWiringStoreURL: URL? = nil) {
        self.overrides = overrides
        self.toggles = .loadStandard()
        let storeURL = hookWiringStoreURL ?? (try? HookWiringStore.standardURL())
        self.hookWiringStoreURL = storeURL
        self.hookWirings = storeURL.flatMap { try? HookWiringStore.load(from: $0) } ?? HookWiringStore()
        reload()
        refreshPreview()
    }

    // MARK: - Catalog

    func reload() {
        entries = Self.buildCatalog(overrides: overrides)
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

    // No disk write here: the editor reads via the fallback and only a save creates
    // an override, so browsing never pins an asset to its current bundled content.
    func beginEditing(_ entry: CatalogEntry) {
        // A freshly opened editor starts clean; the new DocEditorView reconfirms via
        // onDirtyChange once it loads. Resetting here avoids a stale Reset button
        // flashing on the next entry during the editor swap.
        isEditorDirty = false
        guard let overrideURL = overrides.overrideURL(forRelative: entry.relativePath) else {
            editingFileURL = overrides.url(forRelative: entry.relativePath)
            editingFallbackURL = nil
            return
        }
        editingFileURL = overrideURL
        let bundled = overrides.bundledRoot.appending(path: entry.relativePath)
        editingFallbackURL =
            FileManager.default.fileExists(atPath: bundled.path) ? bundled : nil
    }

    // Called after the editor saves the given file: the override may now differ
    // from bundled, so refresh its ● marker and the live preview.
    func notifySaved(relativePath: String) {
        refreshOverrideStatus(for: relativePath)
        refreshPreview()
    }

    // Reset is two-phase so the embedded editor can discard its in-flight buffer
    // before we tear it down. Otherwise the editor's autosave-on-disappear would
    // re-create the very override we just deleted (with the unsaved edits). Phase 1
    // bumps the token the editor observes; the editor discards and calls back into
    // `finishReset`, which performs the actual deletion.
    private(set) var editorResetToken = 0
    private var pendingResetEntry: CatalogEntry?

    func resetToDefault(_ entry: CatalogEntry) {
        pendingResetEntry = entry
        editorResetToken += 1
    }

    func finishReset() {
        guard let entry = pendingResetEntry else { return }
        pendingResetEntry = nil
        guard let url = overrides.overrideURL(forRelative: entry.relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
        overriddenPaths.remove(entry.relativePath)
        isEditorDirty = false
        if editingFileURL == url {
            editingFileURL = nil
            editingFallbackURL = nil
            selection = nil
        }
        refreshPreview()
    }

    // MARK: - User-authored templates (override store, no bundled baseline)

    var agentEntries: [CatalogEntry] {
        entries.filter { $0.category == .agents }
    }

    // Create a new override file for `category`, seeded with a per-kind starter, and
    // select it for editing. A name that resolves to an existing catalog entry (a
    // bundled item or an already-added override) selects that entry instead of
    // writing a duplicate. Returns false on an empty/invalid name, a non-addable
    // category, or no override store.
    @discardableResult
    func addTemplate(
        category: Category, name: String, wiring: (event: HookEvent, matcher: String?)? = nil
    ) -> Bool {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty, let overrideRoot = overrides.overrideRoot,
            let plan = Self.newTemplatePlan(category: category, sanitizedName: sanitized)
        else { return false }

        if let existing = entries.first(where: { $0.relativePath == plan.relativePath }) {
            selection = existing.id
            return true
        }

        let url = overrideRoot.appending(path: plan.relativePath)
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                try plan.starter.write(to: url, atomically: true, encoding: .utf8)
            }
            if category == .hooks, let base = Self.hookBaseName(forRelativePath: plan.relativePath) {
                persistWiring(
                    HookWiring(
                        name: base, event: wiring?.event ?? .preToolUse, matcher: wiring?.matcher))
            }
            reload()
            selection = plan.relativePath
            return true
        } catch {
            return false
        }
    }

    // Remove a user-authored override file and prune it from the catalog. A no-op for
    // bundled entries (they reset, they don't delete).
    func delete(_ entry: CatalogEntry) {
        guard entry.userAuthored,
            let url = overrides.overrideURL(forRelative: entry.relativePath)
        else { return }
        // A user skill is a directory: delete the whole `skills/<name>` tree, not
        // just the selected file. Flat kinds delete the single override file.
        let toRemove = (entry.category == .skills ? overrideSkillDirURL(for: entry) : url) ?? url
        try? FileManager.default.removeItem(at: toRemove)
        // A user hook drops its wiring too, so the next scaffold removes it from
        // settings.json as well as the file tree.
        if entry.category == .hooks, let base = Self.hookBaseName(forRelativePath: entry.relativePath) {
            hookWirings.remove(named: base)
            if let storeURL = hookWiringStoreURL { try? hookWirings.save(to: storeURL) }
        }
        overriddenPaths.remove(entry.relativePath)
        if editingFileURL == url {
            editingFileURL = nil
            editingFallbackURL = nil
        }
        if selection == entry.relativePath { selection = nil }
        reload()
    }

    // The override `skills/<name>` directory URL for a skill entry whose relative
    // path is `skills/<name>/…`, or nil if there is no store / malformed path.
    private func overrideSkillDirURL(for entry: CatalogEntry) -> URL? {
        guard let overrideRoot = overrides.overrideRoot else { return nil }
        let comps = entry.relativePath.split(separator: "/")
        guard comps.count >= 2, comps[0] == "skills" else { return nil }
        return overrideRoot.appending(path: "skills/\(comps[1])", directoryHint: .isDirectory)
    }

    // The override relative path and starter content for a new user item, or nil for
    // a category that can't be authored from scratch.
    private static func newTemplatePlan(
        category: Category, sanitizedName: String
    ) -> (relativePath: String, starter: String)? {
        switch category {
        case .agents:
            let file = sanitizedName.hasSuffix(".md") ? sanitizedName : sanitizedName + ".md"
            return ("agents/\(file)", "# \(String(file.dropLast(3)))\n\nDescribe what this agent does.\n")
        case .docs:
            let file = sanitizedName.hasSuffix(".md") ? sanitizedName : sanitizedName + ".md"
            return ("docs/\(file)", "# \(String(file.dropLast(3)))\n\n")
        case .plumageScripts:
            let shebang = sanitizedName.hasSuffix(".py") ? "#!/usr/bin/env python3\n" : "#!/bin/sh\n"
            return ("plumage/\(sanitizedName)", shebang)
        case .skills:
            return ("skills/\(sanitizedName)/SKILL.md", Self.skillStarter(name: sanitizedName))
        case .hooks:
            let base = sanitizedName.hasSuffix(".sh") ? String(sanitizedName.dropLast(3)) : sanitizedName
            return ("hooks/\(base).sh", "#!/bin/sh\n")
        default:
            return nil
        }
    }

    // The hook base name (toggle key / wiring name) for a `hooks/<name>.sh` path.
    private static func hookBaseName(forRelativePath rel: String) -> String? {
        guard rel.hasPrefix("hooks/"), rel.hasSuffix(".sh") else { return nil }
        return String(rel.dropFirst("hooks/".count).dropLast(".sh".count))
    }

    private func persistWiring(_ wiring: HookWiring) {
        hookWirings.upsert(wiring)
        guard let storeURL = hookWiringStoreURL else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? hookWirings.save(to: storeURL)
    }

    private static func skillStarter(name: String) -> String {
        """
        ---
        name: \(name)
        description: Describe when this skill should be used.
        ---

        # \(name)

        Describe what this skill does.
        """ + "\n"
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

    // MARK: - Catalog construction

    private static func buildCatalog(overrides: ScaffoldOverrides) -> [CatalogEntry] {
        var result = bundledEntries(root: overrides.bundledRoot)
        let bundledPaths = Set(result.map(\.relativePath))

        // Agents have no bundled baseline: the catalog is the override store.
        for name in overrides.overrideFileNames(inRelativeDir: "agents") {
            result.append(
                CatalogEntry(
                    relativePath: "agents/\(name)", category: .agents, label: name,
                    userAuthored: true))
        }

        // Docs and plumage scripts: the bundled files are already listed; add any
        // override-only files the user authored (skipping overrides of bundled files,
        // which are the same entries with an override on disk).
        let unionDirs: [(dir: String, category: Category)] = [
            ("docs", .docs), ("plumage", .plumageScripts),
        ]
        for (dir, category) in unionDirs {
            for name in overrides.overrideFileNames(inRelativeDir: dir) {
                let rel = "\(dir)/\(name)"
                guard !bundledPaths.contains(rel) else { continue }
                result.append(
                    CatalogEntry(
                        relativePath: rel, category: category, label: name, userAuthored: true))
            }
        }

        // Hooks: add override-only `.sh` files (overrides of bundled hooks are
        // already listed as bundled entries).
        for name in overrides.overrideFileNames(inRelativeDir: "hooks") where name.hasSuffix(".sh") {
            let rel = "hooks/\(name)"
            guard !bundledPaths.contains(rel) else { continue }
            result.append(
                CatalogEntry(relativePath: rel, category: .hooks, label: name, userAuthored: true))
        }

        // Skills are directories: enumerate each override skill tree and add its
        // override-only files (overrides of bundled skill files are already listed).
        for skill in overrides.overrideSkillDirNames() {
            for sub in overrides.overrideFileNamesRecursive(inRelativeDir: "skills/\(skill)") {
                let rel = "skills/\(skill)/\(sub)"
                guard !bundledPaths.contains(rel) else { continue }
                result.append(
                    CatalogEntry(
                        relativePath: rel, category: .skills, label: "\(skill)/\(sub)",
                        userAuthored: true))
            }
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
                CatalogEntry(
                    relativePath: rel, category: category,
                    label: label(for: rel, category: category), userAuthored: false))
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
