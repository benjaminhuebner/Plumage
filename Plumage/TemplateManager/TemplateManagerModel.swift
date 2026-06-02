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

    private let store: TemplateCatalogStore
    private let overrides: ScaffoldOverrides

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
            return
        }
        contentFiles = fileNodes(for: selection)
        membership = membershipInfo(for: selection)
        if let current = selectedFile, contentFiles.contains(current) { return }
        selectedFile = contentFiles.first
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
