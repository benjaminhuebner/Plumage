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

    func buildContentTree(for item: TemplateCatalogItem) -> [FileNode] {
        switch item {
        case .base:
            var leaves = baseLeafSpecs().compactMap { spec in
                fileNode(relative: spec.relative, displayName: spec.name).map { (spec.output, $0) }
            }
            // Generated configs always show (even with no override yet).
            leaves += ManagerConfig.allCases.map { ($0.relativePath, configNode($0)) }
            return Self.assembleTree(leaves: leaves, bundledRoot: overrides.bundledRoot)
        case .sharedComponent, .template:
            return fileNodesForFragments(item)
        }
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

    // MARK: - Base output tree

    private func baseLeafSpecs() -> [LeafSpec] {
        var specs: [LeafSpec] = []
        func add(output: String, relative: String, name: String? = nil) {
            specs.append(
                LeafSpec(output: output, relative: relative, name: name ?? (output as NSString).lastPathComponent))
        }

        add(output: ".claude/CLAUDE.md", relative: catalog.base.claudeMdRelativePath)

        for hook in catalog.base.workflowHooks {
            add(output: ".claude/hooks/\(hook).sh", relative: "hooks/\(hook).sh")
        }
        for name in overrides.overrideFileNames(inRelativeDir: "hooks") where name.hasSuffix(".sh") {
            add(output: ".claude/hooks/\(name)", relative: "hooks/\(name)")
        }

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

        for script in overrides.unionFileNames(inRelativeDir: "plumage") {
            add(output: ".plumage/scripts/\(script)", relative: "plumage/\(script)")
        }

        // Bundled Swift tooling configs land at the project root.
        add(output: ".swift-format", relative: "configs/swift-format")
        add(output: ".swiftlint.yml", relative: "configs/swiftlint.yml")

        return specs
    }

    // Template / shared component: the contributing fragment files as flat roots.
    private func fileNodesForFragments(_ item: TemplateCatalogItem) -> [FileNode] {
        switch item {
        case .base: return []
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else { return [] }
            return component.files.compactMap { file in
                fileNode(
                    relative: relativePath(for: component.kind, file: file),
                    displayName: component.kind == .layer ? file : nil)
            }
        case .template(let id):
            guard let template = catalog.template(id: id) else { return [] }
            return template.templateLayers.compactMap {
                fileNode(relative: "templates/\($0)/CLAUDE.md", displayName: $0)
            }
        }
    }

    // MARK: - Tree assembly

    // Folds `(outputPath, leaf)` pairs into a nested `FileNode` tree. Intermediate
    // path components become directory nodes; each leaf keeps the resolved file node
    // (with its override-store `relativePath`) at its output position. Within a level,
    // files sort before folders, each alphabetically — so root configs sit above the
    // `.claude/` subtree (D2).
    static func assembleTree(leaves: [(output: String, node: FileNode)], bundledRoot: URL) -> [FileNode] {
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
