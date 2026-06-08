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
    // `.claude/CLAUDE.md`, never a flat layer name. What populates it differs: Base shows
    // the full project surfaces; a Template and a Shared Component each show only their
    // own deltas — the files that tier owns, nothing inherited (#00084 / #00078).
    func buildContentTree(for item: TemplateCatalogItem) -> [FileNode] {
        let scope = ManagerScope.scope(for: item)
        var leaves = leafSpecs(for: item).compactMap { spec in
            fileNode(relative: spec.relative, displayName: spec.name).map { (spec.output, $0) }
        }
        if showsConfigs(item) {
            // Generated configs always show (even with no override yet).
            leaves += ManagerConfig.allCases.map { ($0.relativePath, configNode($0)) }
        }
        // User-created (possibly empty) folders show at their output positions — read
        // inside the scope subtree (#00078) and mapped back to the project layout.
        let root = scope.storageRoot
        let directories =
            showsLooseSurfaces(item)
            ? overrides.overrideDirectoryPaths(inRoot: root).compactMap {
                Self.outputPath(forStorageDir: root.isEmpty ? $0 : "\(root)/\($0)", scope: scope)
            } : []
        return Self.assembleTree(
            leaves: leaves, directories: directories, bundledRoot: overrides.bundledRoot)
    }

    // Only Base carries the generated project configs (settings, gitignore, …). A
    // Template shows just its own deltas (#00084 delta view) and a Shared Component is a
    // focused sub-bundle — neither repeats Base's generated configs.
    private func showsConfigs(_ item: TemplateCatalogItem) -> Bool {
        switch item {
        case .base: return true
        case .template, .sharedComponent: return false
        }
    }

    // Every tier owns and shows its own loose files (docs/skills/agents/arbitrary) and
    // user-created folders — that ownership is what stops a file leaking into all
    // templates (#00078).
    private func showsLooseSurfaces(_ item: TemplateCatalogItem) -> Bool { true }

    private func leafSpecs(for item: TemplateCatalogItem) -> [LeafSpec] {
        switch item {
        case .base:
            return surfaceSpecs(
                scope: .base, showsConfigs: true,
                hookFiles: hookLeafFileNames(effectiveBases: catalog.base.workflowHooks),
                claudeMdStorage: catalog.base.claudeMdRelativePath)
        case .template(let id):
            guard let template = catalog.template(id: id) else { return [] }
            // A Template shows only its own deltas (#00084): its own CLAUDE.md layer (no
            // Base fallback) plus the loose files it owns under `templates/<id>/`. No Base
            // hooks, no issues slot, no generated configs — those are inherited, not the
            // template's, so two templates render visibly distinct minimal trees.
            var specs: [LeafSpec] = []
            if let ownLayer = template.templateLayers.first {
                specs.append(
                    LeafSpec(
                        output: ".claude/CLAUDE.md",
                        relative: ScaffoldOverrides.layerRelativePath(ownLayer), name: "CLAUDE.md"))
            }
            specs += surfaceSpecs(scope: .template(id), showsConfigs: false)
            return specs
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else { return [] }
            return componentLeafSpecs(component)
        }
    }

    // MARK: - Output ⇄ override-store path mapping

    // Inverse of `outputPath(forStorageDir:)`: output-tree paths and override-store
    // paths are distinct spaces, so a dropped/created item maps back before it's written.
    // The `scope` prefixes the resulting store dir with the owning tier's root (#00078);
    // `.base` (the default) keeps the historical un-prefixed store paths.
    nonisolated static func storageDir(
        forOutputFolder output: String, scope: ManagerScope = .base
    )
        -> String
    {
        let baseDir: String
        if output.isEmpty {
            baseDir = ""
        } else if output == ".claude" {
            // The real `.claude/` root: arbitrary loose files live directly under it
            // (`.claude/bla.md`), distinct from the store root (#00084).
            baseDir = ".claude"
        } else if output.hasPrefix(".claude/") {
            let rest = String(output.dropFirst(".claude/".count))
            let head = rest.split(separator: "/").first.map(String.init) ?? rest
            // Typed namespaces (docs/skills/agents, plus hooks/issues at Base) are hoisted
            // out of `.claude/` in the store; any other `.claude/` path is arbitrary and
            // keeps the prefix — the strict inverse of `outputPath` (#00084).
            baseDir = claudeHoistedTopLevel(for: scope).contains(head) ? rest : ".claude/\(rest)"
        } else {
            // An arbitrary project-root folder maps to the same store path (the inverse
            // of `outputPath(forStorageDir:)`), so adding into it lands inside it.
            baseDir = output
        }
        let root = scope.storageRoot
        if root.isEmpty { return baseDir }
        return baseDir.isEmpty ? root : "\(root)/\(baseDir)"
    }

    // The store top-level dirs whose contents are hoisted out of `.claude/` in the output:
    // typed loose namespaces shown under `.claude/<name>` but stored without the prefix.
    // At Base every loose `.claude` namespace; inside a tier only docs/skills/agents
    // (`hooks`/`issues` aren't loose there, so a tier folder so named is arbitrary, #00078).
    // Couples `storageDir` ⇄ `outputPath`; the arbitrary `.claude/<path>` namespace is the
    // complement that is *not* hoisted and lives under `<scopeRoot>/.claude/` (#00084).
    nonisolated static func claudeHoistedTopLevel(for scope: ManagerScope) -> Set<String> {
        switch scope {
        case .base: return ["hooks", "docs", "skills", "agents", "issues"]
        case .template, .component: return ["docs", "skills", "agents"]
        }
    }

    // Surfaced through their own typed walks (or internal), so the arbitrary-root-files
    // scan must skip them to avoid showing the same file twice. `.claude` is deliberately
    // *not* here: it is now a real arbitrary namespace (`<root>/.claude/<path>`) the scan
    // must surface so a loose file dropped onto `.claude` stays visible (#00084).
    static let typedStoreTopLevel: Set<String> = [
        "hooks", "docs", "skills", "agents", "issues",
        "templates", "components", "template-images", "configs",
    ]

    // The output position a stored directory shows at, or nil for store dirs that are
    // not surfaces of `scope` (template layers, gitignore fragments, imported images, or
    // a sibling tier's subtree). The scope root is stripped first so a tier's loose dir
    // lands at the same `.claude/...` position regardless of which tier owns it (#00078).
    static func outputPath(forStorageDir storage: String, scope: ManagerScope = .base) -> String? {
        let root = scope.storageRoot
        let stripped: String
        if root.isEmpty {
            stripped = storage
        } else if storage == root {
            return nil  // the scope root itself is not a project folder
        } else if storage.hasPrefix(root + "/") {
            stripped = String(storage.dropFirst(root.count + 1))
        } else {
            return nil  // belongs to a different scope
        }
        guard !stripped.isEmpty else { return nil }
        let first = stripped.split(separator: "/").first.map(String.init) ?? stripped
        // `templates`/`components` guard Base's scan from dumping sibling-tier subtrees.
        if ["templates", "components", "template-images", "configs"].contains(first) { return nil }
        // A real `.claude/` store path (arbitrary loose files, or the `.claude` dir itself)
        // already carries the prefix the output uses — map it straight back (#00084).
        if first == ".claude" { return stripped }
        // Typed loose namespaces are stored without the `.claude/` prefix but shown under
        // it; the hoisted set is scope-aware and shared with `storageDir` (#00078/#00084).
        if claudeHoistedTopLevel(for: scope).contains(first) { return ".claude/\(stripped)" }
        return stripped  // arbitrary store-root directory → project root
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

    // Real filenames for the hook slots a tree shows: each effective base resolves to
    // its real override file (so a `.py`/`.rb` hook displays with its extension) or the
    // default `<base>.sh` for built-ins, plus any override-only hook files not already
    // covered by an effective base. De-duplication by output happens in `surfaceSpecs`.
    private func hookLeafFileNames(effectiveBases: [String]) -> [String] {
        let overrideFiles = overrides.overrideFileNames(inRelativeDir: "hooks")
        var fileByBase: [String: String] = [:]
        for file in overrideFiles { fileByBase[(file as NSString).deletingPathExtension] = file }
        var names = effectiveBases.map { fileByBase[$0] ?? "\($0).sh" }
        let coveredBases = Set(effectiveBases)
        for file in overrideFiles
        where !coveredBases.contains((file as NSString).deletingPathExtension) {
            names.append(file)
        }
        return names
    }

    // The typed top-level dirs of a `scope`'s arbitrary-file scan: at the store root
    // (Base) every typed namespace; inside a tier subtree only the loose category dirs
    // (the composition dirs — hooks, configs — never live under a scope root).
    private static func scopedTypedTopLevel(for scope: ManagerScope) -> Set<String> {
        switch scope {
        case .base: return typedStoreTopLevel
        case .template, .component: return ["docs", "skills", "agents"]
        }
    }

    // The project surfaces in their output positions. `showsConfigs` adds the generated
    // configs and composition slots (CLAUDE.md → `claudeMdStorage`, hooks, issues) for
    // Base/Templates; a Component passes `false` and supplies those from its manifest.
    // The loose surfaces (docs/skills/agents/arbitrary) are always read inside the
    // scope's store root so they belong to one tier only (#00078); their output stays
    // `.claude/...`, only `relative` carries the scope prefix. De-duplicates by output.
    private func surfaceSpecs(
        scope: ManagerScope, showsConfigs: Bool, hookFiles: [String] = [],
        claudeMdStorage: String? = nil
    ) -> [LeafSpec] {
        var specs: [LeafSpec] = []
        var seen = Set<String>()
        // A bundled file the user moved away (tombstoned) must vanish from its old
        // position — skip any suppressed store path.
        let suppressed = overrides.suppressedRelativePaths()
        let root = scope.storageRoot
        func scoped(_ rel: String) -> String { root.isEmpty ? rel : "\(root)/\(rel)" }
        func add(output: String, relative: String, name: String? = nil) {
            guard !suppressed.contains(relative) else { return }
            guard seen.insert(output).inserted else { return }
            specs.append(
                LeafSpec(
                    output: output, relative: relative,
                    name: name ?? (output as NSString).lastPathComponent))
        }

        if showsConfigs {
            if let claudeMdStorage {
                add(output: ".claude/CLAUDE.md", relative: claudeMdStorage, name: "CLAUDE.md")
            }
            for file in hookFiles { add(output: ".claude/hooks/\(file)", relative: "hooks/\(file)") }
            add(output: ".claude/issues/_TEMPLATE.md", relative: "issues/_TEMPLATE.md")
        }
        for doc in overrides.unionFileNames(inRelativeDir: scoped("docs")) {
            add(output: ".claude/docs/\(doc)", relative: scoped("docs/\(doc)"))
        }
        for sub in overrides.unionFileNamesRecursive(inRelativeDir: scoped("skills")) {
            add(output: ".claude/skills/\(sub)", relative: scoped("skills/\(sub)"))
        }
        for agent in overrides.overrideFileNames(inRelativeDir: scoped("agents")) {
            add(output: ".claude/agents/\(agent)", relative: scoped("agents/\(agent)"))
        }
        if showsConfigs {
            // Bundled Swift tooling configs land at the project root.
            add(output: ".swift-format", relative: "configs/swift-format")
            add(output: ".swiftlint.yml", relative: "configs/swiftlint.yml")
        }
        // Arbitrary user-authored files anywhere outside the typed category dirs show at
        // their output position (e.g. `.editorconfig` at root, or `myfolder/x.txt` inside
        // a user-created folder), minus the generated configs already shown as nodes.
        let configPaths = Set(ManagerConfig.allCases.map(\.relativePath))
        let arbitrary = overrides.overrideRootArbitraryFiles(
            inRoot: root, excludingTopLevel: Self.scopedTypedTopLevel(for: scope))
        for path in arbitrary where !configPaths.contains(scoped(path)) {
            add(output: path, relative: scoped(path))
        }
        return specs
    }

    // A Shared Component's tree: its composition refs (layer → `.claude/CLAUDE.md`, hook
    // → `.claude/hooks/<name>.sh`, plus legacy skill/config memberships) followed by the
    // loose files it owns under `components/<id>/` — read through the same scoped
    // surface machinery as Base/Templates, just without the project configs (#00078).
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
                let fileName = hookFileName(forBase: name)
                specs.append(
                    LeafSpec(
                        output: ".claude/hooks/\(fileName)", relative: "hooks/\(fileName)",
                        name: fileName))
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
        let composition = specs.filter { !suppressed.contains($0.relative) }
        // The component's own loose files (docs/skills/agents/arbitrary) under
        // `components/<id>/` — no project configs, no CLAUDE.md/hook slots.
        let loose = surfaceSpecs(scope: .component(component.id), showsConfigs: false)
        return composition + loose
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
