import Foundation

// Feature-local model for the Templates settings tab. Owns the catalog of bundled
// scaffold assets, the override read/write, the enable/disable toggles, the agents
// store and the live CLAUDE.md preview. State-as-bridge: disk I/O is funnelled
// through this @MainActor type so the view stays declarative.
//
// Editing model: `DocEditorView` loads from and saves to a single file URL, so to
// edit a bundled asset the model seeds its override slot with the bundled content
// on first open and points the editor at the override URL. A file therefore shows
// as overridden (●) once opened for editing; reset-to-default deletes the override.
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

    init(overrides: ScaffoldOverrides = .standard()) {
        self.overrides = overrides
        reload()
    }

    // MARK: - Catalog

    func reload() {
        entries = Self.buildCatalog(overrides: overrides)
        overriddenPaths = Set(
            entries.map(\.relativePath).filter { overrides.hasOverride(forRelative: $0) })
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

    // MARK: - Editing

    func beginEditing(_ entry: CatalogEntry) {
        do {
            editingFileURL = try ensureOverride(for: entry)
            overriddenPaths.insert(entry.relativePath)
        } catch {
            editingFileURL = nil
        }
    }

    func resetToDefault(_ entry: CatalogEntry) {
        guard let url = overrides.overrideURL(forRelative: entry.relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
        overriddenPaths.remove(entry.relativePath)
        if editingFileURL == url {
            editingFileURL = nil
            selection = nil
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
