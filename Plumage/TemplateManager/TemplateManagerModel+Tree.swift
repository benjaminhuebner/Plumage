import Foundation

// Builds the content column's hierarchical node tree. For Base the tree mirrors the
// scaffolded project layout (D2): root configs plus a `.claude/` / `.plumage/`
// subtree. Each leaf keeps its override-store `relativePath` (so editing, ● markers,
// reset and delete keep working unchanged) while its position in the tree follows
// the output path. Template and shared-component selections show their contributing
// fragment files directly — those are manifest membership, not a free-form tree.
extension TemplateManagerModel {
    // One file destined for the scaffolded project: where it lands (`output`, drives
    // tree placement) and where its bytes live in the override store (`relative`).
    struct LeafSpec {
        let output: String
        let relative: String
        let name: String
    }

    // Every selection renders the same `.claude/`-mirroring output structure (D2), so
    // a hook is always shown under `.claude/hooks` and a CLAUDE.md fragment as
    // `.claude/CLAUDE.md`, never a flat layer name. What populates it differs:
    // Base and a Template show the full project surfaces (a Template swaps in its own
    // CLAUDE.md fragment); a Shared Component shows just its own files.
    func buildContentTree(for item: TemplateCatalogItem) -> [FileNode] {
        var leaves = leafSpecs(for: item).compactMap { spec in
            fileNode(relative: spec.relative, displayName: spec.name).map { (spec.output, $0) }
        }
        if showsProjectSurfaces(item) {
            // Generated configs always show (even with no override yet).
            leaves += ManagerConfig.allCases.map { ($0.relativePath, configNode($0)) }
        }
        // User-created (possibly empty) folders show at their output positions.
        let directories =
            showsProjectSurfaces(item)
            ? overrides.overrideDirectoryPaths().compactMap(Self.outputPath(forStorageDir:)) : []
        return Self.assembleTree(
            leaves: leaves, directories: directories, bundledRoot: overrides.bundledRoot)
    }

    // Base and Templates are full project profiles (configs + arbitrary global files);
    // a Shared Component is a focused sub-bundle showing only its own files.
    private func showsProjectSurfaces(_ item: TemplateCatalogItem) -> Bool {
        switch item {
        case .base, .template: return true
        case .sharedComponent: return false
        }
    }

    private func leafSpecs(for item: TemplateCatalogItem) -> [LeafSpec] {
        switch item {
        case .base:
            return globalSurfaceSpecs(
                hookNames: baseHookNames(), claudeMdStorage: catalog.base.claudeMdRelativePath)
        case .template(let id):
            guard let template = catalog.template(id: id) else { return [] }
            // A Template shows the merged project surfaces with its own CLAUDE.md
            // fragment swapped in (its effective hooks include its components' hooks).
            let ownLayer = template.templateLayers.first
            let claudeMdStorage =
                ownLayer.map(ScaffoldOverrides.layerRelativePath) ?? catalog.base.claudeMdRelativePath
            return globalSurfaceSpecs(
                hookNames: catalog.effectiveHooks(forTemplate: id) + overrideHookBaseNames(),
                claudeMdStorage: claudeMdStorage)
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else { return [] }
            return componentLeafSpecs(component)
        }
    }

    // MARK: - Output ⇄ override-store path mapping

    // Inverse of `outputPath(forStorageDir:)`: output-tree paths and override-store
    // paths are distinct spaces, so a dropped/created item maps back before it's written.
    nonisolated static func storageDir(forOutputFolder output: String) -> String {
        if output.isEmpty || output == ".claude" { return "" }
        if output.hasPrefix(".claude/") { return String(output.dropFirst(".claude/".count)) }
        // An arbitrary project-root folder maps to the same store path (the inverse of
        // `outputPath(forStorageDir:)`), so adding into it lands inside it, not at root.
        return output
    }

    // Surfaced through their own typed walks (or internal), so the arbitrary-root-files
    // scan must skip them to avoid showing the same file twice.
    static let typedStoreTopLevel: Set<String> = [
        "hooks", "docs", "skills", "agents", "issues",
        "templates", "template-images", "configs", ".claude",
    ]

    // The output position a stored directory shows at, or nil for store dirs that are
    // not Base surfaces (template layers, gitignore fragments, imported images).
    static func outputPath(forStorageDir storage: String) -> String? {
        let first = storage.split(separator: "/").first.map(String.init) ?? storage
        if ["templates", "template-images", "configs"].contains(first) { return nil }
        if ["hooks", "docs", "skills", "agents", "issues"].contains(first) { return ".claude/\(storage)" }
        return storage  // arbitrary store-root directory → project root
    }

    // The flat list of leaves the content column derives its selection from — every
    // file in the tree, folders excluded. Kept flat so selection retention, add,
    // import and the ● marker set all work off a single sequence.
    static func flattenLeaves(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node -> [FileNode] in
            if let children = node.children { return flattenLeaves(children) }
            return [node]
        }
    }

    // Depth-first search for a node by its `relativePath` (a leaf's store path or a
    // folder's output path), used to re-select a freshly created item.
    static func findNode(in nodes: [FileNode], relativePath: String) -> FileNode? {
        for node in nodes {
            if node.relativePath == relativePath { return node }
            if let children = node.children,
                let found = findNode(in: children, relativePath: relativePath)
            {
                return found
            }
        }
        return nil
    }

    // MARK: - Folder marker aggregation

    // A directory carries a dimmed ● when any descendant file is overridden, so a
    // collapsed folder still signals that something inside diverges from the default.
    func aggregateOverridden(_ node: FileNode) -> Bool {
        guard let children = node.children else { return false }
        return children.contains { $0.isDirectory ? aggregateOverridden($0) : isOverridden($0) }
    }

    // A directory carries a ⚠ when any descendant hook still needs wiring.
    func aggregateNeedsWiring(_ node: FileNode) -> Bool {
        guard let children = node.children else { return false }
        return children.contains { $0.isDirectory ? aggregateNeedsWiring($0) : needsWiring($0) }
    }

    // MARK: - Leaf specs

    // Base names of the workflow hooks plus any user override-only hooks.
    private func baseHookNames() -> [String] {
        catalog.base.workflowHooks + overrideHookBaseNames()
    }

    private func overrideHookBaseNames() -> [String] {
        overrides.overrideFileNames(inRelativeDir: "hooks")
            .filter { $0.hasSuffix(".sh") }
            .map { String($0.dropLast(3)) }
    }

    // The full project surfaces in their output positions, with the CLAUDE.md slot
    // pointed at `claudeMdStorage` (the base skeleton for Base, a template's own layer
    // for a Template). De-duplicates by output path so a hook listed twice collapses.
    private func globalSurfaceSpecs(hookNames: [String], claudeMdStorage: String) -> [LeafSpec] {
        var specs: [LeafSpec] = []
        var seen = Set<String>()
        // A bundled file the user moved away (tombstoned) must vanish from its old
        // position — skip any suppressed store path.
        let suppressed = overrides.suppressedRelativePaths()
        func add(output: String, relative: String, name: String? = nil) {
            guard !suppressed.contains(relative) else { return }
            guard seen.insert(output).inserted else { return }
            specs.append(
                LeafSpec(
                    output: output, relative: relative,
                    name: name ?? (output as NSString).lastPathComponent))
        }

        add(output: ".claude/CLAUDE.md", relative: claudeMdStorage, name: "CLAUDE.md")
        for hook in hookNames { add(output: ".claude/hooks/\(hook).sh", relative: "hooks/\(hook).sh") }
        add(output: ".claude/issues/_TEMPLATE.md", relative: "issues/_TEMPLATE.md")
        for doc in overrides.unionFileNames(inRelativeDir: "docs") {
            add(output: ".claude/docs/\(doc)", relative: "docs/\(doc)")
        }
        for sub in overrides.unionFileNamesRecursive(inRelativeDir: "skills") {
            add(output: ".claude/skills/\(sub)", relative: "skills/\(sub)")
        }
        for agent in overrides.overrideFileNames(inRelativeDir: "agents") {
            add(output: ".claude/agents/\(agent)", relative: "agents/\(agent)")
        }
        // Bundled Swift tooling configs land at the project root.
        add(output: ".swift-format", relative: "configs/swift-format")
        add(output: ".swiftlint.yml", relative: "configs/swiftlint.yml")
        // Arbitrary user-authored files anywhere outside the typed category dirs show at
        // their store path (e.g. `.editorconfig` at root, or `myfolder/x.txt` inside a
        // user-created folder), minus the generated configs already shown as nodes.
        let configPaths = Set(ManagerConfig.allCases.map(\.relativePath))
        let arbitrary = overrides.overrideRootArbitraryFiles(excludingTopLevel: Self.typedStoreTopLevel)
        for path in arbitrary where !configPaths.contains(path) {
            add(output: path, relative: path)
        }
        return specs
    }

    // A Shared Component's own files, placed in the output structure (its hooks under
    // `.claude/hooks`, its layer as `.claude/CLAUDE.md`, its skill subtree under
    // `.claude/skills/<name>/`). Same folder convention as everywhere else.
    private func componentLeafSpecs(_ component: SharedComponent) -> [LeafSpec] {
        let suppressed = overrides.suppressedRelativePaths()
        var specs: [LeafSpec] = []
        for file in component.files {
            let name = file.name
            switch file.kind {
            case .layer:
                specs.append(
                    LeafSpec(
                        output: ".claude/CLAUDE.md", relative: ScaffoldOverrides.layerRelativePath(name),
                        name: "CLAUDE.md"))
            case .hook:
                specs.append(
                    LeafSpec(
                        output: ".claude/hooks/\(name).sh", relative: "hooks/\(name).sh",
                        name: "\(name).sh"))
            case .skill:
                let subs = overrides.unionFileNamesRecursive(inRelativeDir: "skills/\(name)")
                let entries = subs.isEmpty ? ["SKILL.md"] : subs
                for sub in entries {
                    specs.append(
                        LeafSpec(
                            output: ".claude/skills/\(name)/\(sub)",
                            relative: "skills/\(name)/\(sub)", name: (sub as NSString).lastPathComponent))
                }
            case .config:
                specs.append(
                    LeafSpec(output: ".claude/\(name)", relative: "configs/\(name)", name: name))
            }
        }
        return specs.filter { !suppressed.contains($0.relative) }
    }

    // MARK: - Tree assembly

    // Folds `(outputPath, leaf)` pairs into a nested `FileNode` tree. Intermediate
    // path components become directory nodes; each leaf keeps the resolved file node
    // (with its override-store `relativePath`) at its output position. Within a level,
    // files sort before folders, each alphabetically — so root configs sit above the
    // `.claude/` subtree (D2).
    static func assembleTree(
        leaves: [(output: String, node: FileNode)], directories: [String] = [], bundledRoot: URL
    ) -> [FileNode] {
        final class Builder {
            var children: [String: Builder] = [:]
            var order: [String] = []
            var leaf: FileNode?
            func child(_ key: String) -> Builder {
                if let existing = children[key] { return existing }
                let made = Builder()
                children[key] = made
                order.append(key)
                return made
            }
        }

        let root = Builder()
        for (output, node) in leaves {
            let components = output.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var cursor = root
            for component in components.dropLast() { cursor = cursor.child(component) }
            cursor.child(components[components.count - 1]).leaf = node
        }
        // Ensure user-created (possibly empty) folders exist even with no leaf inside.
        for directory in directories {
            var cursor = root
            for component in directory.split(separator: "/").map(String.init) {
                cursor = cursor.child(component)
            }
        }

        func convert(_ builder: Builder, prefix: String) -> [FileNode] {
            let nodes = builder.order.compactMap { key -> FileNode? in
                guard let child = builder.children[key] else { return nil }
                let path = prefix.isEmpty ? key : "\(prefix)/\(key)"
                if let leaf = child.leaf { return leaf }
                return FileNode(
                    url: bundledRoot.appending(path: path, directoryHint: .isDirectory),
                    relativePath: path, name: key, isDirectory: true,
                    children: convert(child, prefix: path))
            }
            return nodes.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return !lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        return convert(root, prefix: "")
    }
}
