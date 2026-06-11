import Foundation

nonisolated enum TemplateArchiveSelection: Equatable, Sendable {
    case base
    case template(String)
    case sharedComponent(String)
    case fullCatalog
}

nonisolated enum TemplateArchiveExportError: Error, Equatable {
    case unknownItem(String)
    case missingImageFile(String)

    var displayMessage: String {
        switch self {
        case .unknownItem(let id):
            return "Can't export \"\(id)\": the item no longer exists."
        case .missingImageFile(let path):
            return "Can't export: the template image \"\(path)\" is missing on disk."
        }
    }
}

nonisolated struct TemplateArchiveExporter: Sendable {
    static let manifestFileName = "archive-manifest.json"

    let catalog: TemplateCatalog
    let overrides: ScaffoldOverrides
    let hookWirings: HookWiringStore
    private let zip: TemplateArchiveZip

    init(
        catalog: TemplateCatalog,
        overrides: ScaffoldOverrides,
        hookWirings: HookWiringStore,
        zip: TemplateArchiveZip = TemplateArchiveZip()
    ) {
        self.catalog = catalog
        self.overrides = overrides
        self.hookWirings = hookWirings
        self.zip = zip
    }

    func export(_ selection: TemplateArchiveSelection, to archiveURL: URL) async throws {
        let manifest = try archiveManifest(for: selection)
        let files = try stagedRelativePaths(for: selection)

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appending(path: "template-archive-export-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: staging.appending(path: Self.manifestFileName), options: .atomic)

        for relative in files {
            guard let source = overrides.overrideURL(forRelative: relative) else { continue }
            let target = staging.appending(path: relative)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try await zip.pack(directory: staging, to: archiveURL)
    }

    // MARK: - Manifest records

    func archiveManifest(for selection: TemplateArchiveSelection) throws -> TemplateArchiveManifest {
        let wirings = try wirings(forStagedPaths: stagedRelativePaths(for: selection))
        switch selection {
        case .base:
            return TemplateArchiveManifest(base: catalog.base, hookWirings: wirings)
        case .template(let id):
            guard let template = catalog.template(id: id) else {
                throw TemplateArchiveExportError.unknownItem(id)
            }
            let members = catalog.sharedComponents(forTemplate: id)
            let category = catalog.category(id: template.categoryID)
            return TemplateArchiveManifest(
                categories: category.map { [$0] } ?? [],
                sharedComponents: members,
                templates: [template],
                hookWirings: wirings
            )
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else {
                throw TemplateArchiveExportError.unknownItem(id)
            }
            return TemplateArchiveManifest(sharedComponents: [component], hookWirings: wirings)
        case .fullCatalog:
            return TemplateArchiveManifest(
                base: catalog.base,
                categories: catalog.sortedCategories,
                sharedComponents: catalog.sortedSharedComponents,
                templates: catalog.templates,
                tombstones: catalog.manifest.tombstones,
                hookWirings: wirings
            )
        }
    }

    // MARK: - Overlay-only file collection

    // Only files that exist in the override store are staged: custom items live
    // entirely there, pristine predefined items contribute no files at all.
    func stagedRelativePaths(for selection: TemplateArchiveSelection) throws -> [String] {
        var paths = Set<String>()
        switch selection {
        case .base:
            paths.formUnion(basePaths())
        case .template(let id):
            guard let template = catalog.template(id: id) else {
                throw TemplateArchiveExportError.unknownItem(id)
            }
            try paths.formUnion(templatePaths(template))
            for member in catalog.sharedComponents(forTemplate: id) {
                paths.formUnion(componentPaths(member))
            }
        case .sharedComponent(let id):
            guard let component = catalog.sharedComponent(id: id) else {
                throw TemplateArchiveExportError.unknownItem(id)
            }
            paths.formUnion(componentPaths(component))
        case .fullCatalog:
            // tombstones.json is store metadata (suppressed bundled files), not
            // item content — deletions travel as manifest tombstone records.
            paths.formUnion(
                overrides.overrideFileNamesRecursive(inRelativeDir: "")
                    .filter { $0 != ScaffoldOverrides.tombstonesFileName })
        }
        return paths.sorted()
    }

    private func templatePaths(_ template: TemplateDescriptor) throws -> Set<String> {
        var paths = Set<String>()
        for layer in template.templateLayers {
            let layerPath = ScaffoldOverrides.layerRelativePath(layer)
            if overrides.hasOverride(forRelative: layerPath) { paths.insert(layerPath) }
        }
        paths.formUnion(subtreePaths(under: "templates/\(template.id)"))
        if case .file(let imagePath) = template.image {
            guard overrides.hasOverride(forRelative: imagePath) else {
                throw TemplateArchiveExportError.missingImageFile(imagePath)
            }
            paths.insert(imagePath)
        }
        return paths
    }

    private func componentPaths(_ component: SharedComponent) -> Set<String> {
        var paths = Set<String>()
        for file in component.files {
            switch file.kind {
            case .layer:
                let layerPath = ScaffoldOverrides.layerRelativePath(file.name)
                if overrides.hasOverride(forRelative: layerPath) { paths.insert(layerPath) }
            case .hook:
                let hookPath = "hooks/\(hookFileName(forBase: file.name))"
                if overrides.hasOverride(forRelative: hookPath) { paths.insert(hookPath) }
            case .config:
                let configPath = "configs/\(file.name)"
                if overrides.hasOverride(forRelative: configPath) { paths.insert(configPath) }
            case .skill:
                paths.formUnion(subtreePaths(under: "skills/\(file.name)"))
            }
        }
        paths.formUnion(subtreePaths(under: "components/\(component.id)"))
        return paths
    }

    // Base owns everything outside the template/component/image namespaces; its
    // own CLAUDE.md lives at `templates/CLAUDE.md` and is re-added explicitly.
    private func basePaths() -> Set<String> {
        var paths = Set<String>(
            overrides.overrideFileNamesRecursive(inRelativeDir: "").filter { path in
                guard path != ScaffoldOverrides.tombstonesFileName else { return false }
                let first = path.split(separator: "/").first.map(String.init) ?? path
                return !["templates", "components", "template-images"].contains(first)
            })
        let claudeMd = catalog.base.claudeMdRelativePath
        if overrides.hasOverride(forRelative: claudeMd) { paths.insert(claudeMd) }
        return paths
    }

    private func subtreePaths(under relativeDir: String) -> Set<String> {
        Set(
            overrides.overrideFileNamesRecursive(inRelativeDir: relativeDir)
                .map { "\(relativeDir)/\($0)" })
    }

    private func hookFileName(forBase base: String) -> String {
        let overrideFiles = overrides.overrideFileNames(inRelativeDir: "hooks")
        return overrideFiles.first { ($0 as NSString).deletingPathExtension == base } ?? "\(base).sh"
    }

    // A wiring travels with the archive only when its hook file is on board.
    private func wirings(forStagedPaths paths: [String]) -> [HookWiring] {
        let stems = Self.hookStems(inPaths: paths)
        return hookWirings.wirings.filter { stems.contains($0.name) }
    }

    // The hook-name stems of every `…/hooks/<file>` path — the join key between
    // archive files and their wirings, shared by export and import.
    static func hookStems(inPaths paths: some Sequence<String>) -> Set<String> {
        var stems = Set<String>()
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            guard components.count >= 2, components[components.count - 2] == "hooks" else { continue }
            stems.insert((components[components.count - 1] as NSString).deletingPathExtension)
        }
        return stems
    }
}
