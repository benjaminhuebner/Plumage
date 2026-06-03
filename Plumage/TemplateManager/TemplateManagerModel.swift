import Foundation

// Read-only membership facts for the middle column: for a template, the shared
// components it includes; for a shared component, the templates that include it.
struct CatalogMembership: Equatable {
    let title: String
    let names: [String]
}

// Scene-scoped state for the Template Manager window. Loads the resolved catalog
// off-main (state-as-bridge), tracks the selected left-column item, and derives
// the middle column's file list + membership for that item. File content is
// resolved through `ScaffoldOverrides` (override-or-bundled), so the browser
// shows the same bytes a new project would scaffold.
@MainActor
@Observable
final class TemplateManagerModel {
    private(set) var catalog: TemplateCatalog = .bundledDefault
    var selection: TemplateCatalogItem? = .base

    private(set) var contentFiles: [FileNode] = []
    private(set) var membership: CatalogMembership?
    var selectedFile: FileNode?

    // Editing state for the right column. The editor saves to the override slot but
    // seeds from the bundled fallback, so merely browsing a file writes nothing —
    // only a real edit materializes an override (mirrors `TemplatesSettingsModel`).
    private(set) var editingFileURL: URL?
    private(set) var editingFallbackURL: URL?

    // Relative paths whose override diverges from the bundled original, mirrored as
    // observed state so the ● markers react to seed/save/reset without polling disk
    // in `body`.
    private(set) var overriddenPaths: Set<String> = []

    // Live dirty state of the embedded editor, so the header can offer Reset to
    // Default on the first keystroke (before any save creates an override).
    private(set) var isEditorDirty = false

    // Two-phase reset: `resetToDefault` bumps the token the editor observes; the
    // editor discards its in-flight buffer and calls back into `finishReset`, which
    // deletes the override. Without the discard, the editor's autosave-on-disappear
    // would re-create the override we just removed.
    private(set) var editorResetToken = 0
    // Forces the mounted editor to remount (and reseed from bundled) after a reset,
    // so the right column shows the reverted content while keeping the file selected.
    private(set) var editorReloadToken = 0
    private var pendingResetPath: String?

    private let store: TemplateCatalogStore
    let overrides: ScaffoldOverrides

    init(
        store: TemplateCatalogStore = TemplateCatalogStore(),
        overrides: ScaffoldOverrides = .standard(bundledRoot: NewProjectAssets.bundledRoot)
    ) {
        self.store = store
        self.overrides = overrides
    }

    func load() async {
        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { store.load() }.value
        catalog = loaded
        if selection == nil { selection = .base }
        refreshContent()
    }

    // Recompute the middle column for the current selection. Called at load and on
    // every left-column selection change (an event boundary, never from `body`).
    func refreshContent() {
        guard let selection else {
            contentFiles = []
            membership = nil
            selectedFile = nil
            beginEditing(nil)
            return
        }
        contentFiles = fileNodes(for: selection)
        membership = membershipInfo(for: selection)
        refreshOverriddenPaths()
        if let current = selectedFile, contentFiles.contains(current) { return }
        selectedFile = contentFiles.first
        beginEditing(selectedFile)
    }

    // MARK: - Editing

    // No disk write: the editor reads via the bundled fallback and only a save creates
    // an override, so opening a file never pins it to its current bundled content.
    // Called on every right-column selection change (an event boundary, not `body`).
    func beginEditing(_ file: FileNode?) {
        isEditorDirty = false
        guard let file, !file.isDirectory,
            let overrideURL = overrides.overrideURL(forRelative: file.relativePath)
        else {
            editingFileURL = nil
            editingFallbackURL = nil
            return
        }
        editingFileURL = overrideURL
        let bundled = overrides.bundledRoot.appending(path: file.relativePath)
        editingFallbackURL =
            FileManager.default.fileExists(atPath: bundled.path) ? bundled : nil
    }

    func setEditorDirty(_ dirty: Bool) {
        if isEditorDirty != dirty { isEditorDirty = dirty }
    }

    // True when the selected file's override diverges from bundled — drives the ●
    // marker. User-authored files (no bundled baseline) are always "overridden".
    func isOverridden(_ file: FileNode) -> Bool {
        overriddenPaths.contains(file.relativePath)
    }

    // A file with no bundled original is user-authored: its header offers Delete
    // rather than Reset to Default.
    func isUserAuthored(_ file: FileNode) -> Bool {
        !overrides.hasBundledOriginal(forRelative: file.relativePath)
    }

    // Called after the editor saves: the override may now differ from bundled, so
    // refresh the file's ● marker.
    func notifySaved(relativePath: String) {
        if overrides.isContentOverridden(forRelative: relativePath) {
            overriddenPaths.insert(relativePath)
        } else {
            overriddenPaths.remove(relativePath)
        }
    }

    // Phase 1 of reset: bump the token the editor observes. The editor discards its
    // buffer and calls `finishReset`. Reachable only from the header's Reset button,
    // shown only while the editor is mounted — so `finishReset` always runs.
    func resetToDefault(_ file: FileNode) {
        pendingResetPath = file.relativePath
        editorResetToken += 1
    }

    // Phase 2: delete the override (revert to bundled) and remount the editor so it
    // reseeds from the bundled original. The file stays selected.
    func finishReset() {
        guard let relativePath = pendingResetPath else { return }
        pendingResetPath = nil
        try? overrides.removeOverride(forRelative: relativePath)
        overriddenPaths.remove(relativePath)
        isEditorDirty = false
        editorReloadToken += 1
    }

    // Delete a user-authored file: remove its override and drop it from the tree. A
    // no-op for bundled-backed files (those reset, they don't delete).
    func delete(_ file: FileNode) {
        guard isUserAuthored(file) else { return }
        try? overrides.removeOverride(forRelative: file.relativePath)
        overriddenPaths.remove(file.relativePath)
        if selectedFile == file {
            selectedFile = nil
            beginEditing(nil)
        }
        refreshContent()
    }

    private func refreshOverriddenPaths() {
        overriddenPaths = Set(
            contentFiles.map(\.relativePath).filter {
                overrides.isContentOverridden(forRelative: $0)
            })
    }

    var selectionTitle: String {
        switch selection {
        case .base: catalog.base.name
        case .sharedComponent(let id): catalog.sharedComponent(id: id)?.name ?? ""
        case .template(let id): catalog.template(id: id)?.name ?? ""
        case nil: ""
        }
    }

    // MARK: - Content derivation

    private func fileNodes(for item: TemplateCatalogItem) -> [FileNode] {
        switch item {
        case .base: return baseFileNodes()
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else { return [] }
            return component.files.compactMap {
                fileNode(relative: relativePath(for: component.kind, file: $0))
            }
        case .template(let id):
            guard let template = catalog.template(id: id) else { return [] }
            return template.templateLayers.compactMap { fileNode(relative: "templates/\($0).md") }
        }
    }

    private func baseFileNodes() -> [FileNode] {
        var nodes: [FileNode] = []
        if let claudeMd = fileNode(relative: catalog.base.claudeMdRelativePath) { nodes.append(claudeMd) }
        for hook in catalog.base.workflowHooks {
            if let node = fileNode(relative: "hooks/\(hook).sh") { nodes.append(node) }
        }
        if let issueTemplate = fileNode(relative: "issues/_TEMPLATE.md") { nodes.append(issueTemplate) }
        for script in overrides.unionFileNames(inRelativeDir: "plumage") {
            if let node = fileNode(relative: "plumage/\(script)") { nodes.append(node) }
        }
        for skill in bundledSkillNames() {
            if let node = fileNode(relative: "skills/\(skill)/SKILL.md", displayName: skill) {
                nodes.append(node)
            }
        }
        return nodes
    }

    private func relativePath(for kind: SharedComponentKind, file: String) -> String {
        switch kind {
        case .layer: "templates/\(file).md"
        case .hook: "hooks/\(file).sh"
        case .skill: "skills/\(file)/SKILL.md"
        case .config: "configs/\(file)"
        }
    }

    // A referenced file missing on disk is omitted from the tree (the code view
    // then shows a placeholder rather than crashing — see the edge cases).
    private func fileNode(relative: String, displayName: String? = nil) -> FileNode? {
        let url = overrides.url(forRelative: relative)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return FileNode(
            url: url, relativePath: relative,
            name: displayName ?? (relative as NSString).lastPathComponent,
            isDirectory: false, children: nil)
    }

    private func bundledSkillNames() -> [String] {
        let dir = overrides.bundledRoot.appending(path: "skills", directoryHint: .isDirectory)
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func membershipInfo(for item: TemplateCatalogItem) -> CatalogMembership? {
        switch item {
        case .base:
            nil
        case .sharedComponent(let id):
            CatalogMembership(
                title: "Included in templates",
                names: catalog.templates(memberOf: id).map(\.name))
        case .template(let id):
            CatalogMembership(
                title: "Included shared components",
                names: catalog.sharedComponents(forTemplate: id).map(\.name))
        }
    }
}
