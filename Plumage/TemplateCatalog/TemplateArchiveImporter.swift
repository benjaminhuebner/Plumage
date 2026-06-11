import Foundation

nonisolated enum TemplateArchiveImportError: Error, Equatable {
    case invalidManifest(String)
    case newerSchema(found: Int, supported: Int)
    case missingImageFile(String)
    case unreferencedImage(String)

    var displayMessage: String {
        switch self {
        case .invalidManifest(let detail):
            return "Not a readable template archive: \(detail.prefix(200))"
        case .newerSchema(let found, let supported):
            return
                "This export comes from a newer Plumage (archive format \(found), this app reads up to \(supported)). Update Plumage to import it."
        case .missingImageFile(let path):
            return "Archive rejected: it references the image \"\(path)\" but doesn't contain it."
        case .unreferencedImage(let path):
            return "Archive rejected: it contains the image \"\(path)\" no template references."
        }
    }
}

nonisolated struct TemplateArchiveItem: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case base
        case template(String)
        case sharedComponent(String)
        case deletedDefaults(count: Int)
    }

    let kind: Kind
    let name: String
    let conflict: Bool
    let files: [String]

    var id: String {
        switch kind {
        case .base: return "base"
        case .template(let templateID): return "template:\(templateID)"
        case .sharedComponent(let componentID): return "component:\(componentID)"
        case .deletedDefaults: return "deleted-defaults"
        }
    }
}

nonisolated struct TemplateArchiveContents: Sendable {
    let stagingDir: URL
    let manifest: TemplateArchiveManifest
    let items: [TemplateArchiveItem]

    func cleanup() {
        try? FileManager.default.removeItem(at: stagingDir)
    }
}

nonisolated struct TemplateArchiveApplyResult: Sendable {
    let catalog: TemplateCatalog
    let hookWirings: HookWiringStore
}

nonisolated struct TemplateArchiveImporter: Sendable {
    let catalog: TemplateCatalog
    let overrides: ScaffoldOverrides
    let bundled: TemplateCatalog
    private let zip: TemplateArchiveZip

    init(
        catalog: TemplateCatalog,
        overrides: ScaffoldOverrides,
        bundled: TemplateCatalog = .bundledDefault,
        zip: TemplateArchiveZip = TemplateArchiveZip()
    ) {
        self.catalog = catalog
        self.overrides = overrides
        self.bundled = bundled
        self.zip = zip
    }

    // MARK: - Read side

    func read(archiveURL: URL) async throws -> TemplateArchiveContents {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "template-archive-import-\(UUID().uuidString)")
        do {
            try await zip.unpack(archive: archiveURL, to: staging)
            return try contents(stagingDir: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func contents(stagingDir: URL) throws -> TemplateArchiveContents {
        let manifest = try readManifest(stagingDir: stagingDir)
        let stagingOverrides = ScaffoldOverrides(
            bundledRoot: overrides.bundledRoot, overrideRoot: stagingDir)
        // The exporter's path collection, run against the staging dir, attributes
        // each unpacked file to its archive item — one mapping for both directions.
        let attribution = TemplateArchiveExporter(
            catalog: TemplateCatalog(
                base: manifest.base ?? bundled.base,
                categories: manifest.categories,
                sharedComponents: manifest.sharedComponents,
                templates: manifest.templates),
            overrides: stagingOverrides,
            hookWirings: HookWiringStore()
        )

        var items: [TemplateArchiveItem] = []
        var claimed = Set<String>()

        var componentFiles: [String: Set<String>] = [:]
        for component in manifest.sharedComponents {
            let files = Set(try attributedPaths(attribution, .sharedComponent(component.id)))
            componentFiles[component.id] = files
            claimed.formUnion(files)
            items.append(
                TemplateArchiveItem(
                    kind: .sharedComponent(component.id),
                    name: component.name,
                    conflict: componentConflict(component, files: files, stagingDir: stagingDir),
                    files: files.sorted()
                ))
        }

        for template in manifest.templates {
            var files = Set(try attributedPaths(attribution, .template(template.id)))
            for memberFiles in componentFiles.values { files.subtract(memberFiles) }
            claimed.formUnion(files)
            items.append(
                TemplateArchiveItem(
                    kind: .template(template.id),
                    name: template.name,
                    conflict: templateConflict(template, files: files, stagingDir: stagingDir),
                    files: files.sorted()
                ))
        }

        if let base = manifest.base {
            var files = Set(try attributedPaths(attribution, .base))
            files.subtract(claimed)
            files.remove(TemplateArchiveExporter.manifestFileName)
            claimed.formUnion(files)
            items.append(
                TemplateArchiveItem(
                    kind: .base,
                    name: base.name,
                    conflict: baseConflict(base, files: files, stagingDir: stagingDir),
                    files: files.sorted()
                ))
        }

        let stagingFiles = stagingOverrides.overrideFileNamesRecursive(inRelativeDir: "")
            .filter { $0 != TemplateArchiveExporter.manifestFileName }
        if let orphanImage = stagingFiles.first(where: {
            $0.hasPrefix("template-images/") && !claimed.contains($0)
        }) {
            throw TemplateArchiveImportError.unreferencedImage(orphanImage)
        }

        if !manifest.tombstones.isEmpty {
            items.append(
                TemplateArchiveItem(
                    kind: .deletedDefaults(count: manifest.tombstones.count),
                    name: "Deleted default items",
                    conflict: tombstoneConflict(manifest.tombstones),
                    files: []
                ))
        }

        let order: (TemplateArchiveItem) -> Int = { item in
            switch item.kind {
            case .base: return 0
            case .sharedComponent: return 1
            case .template: return 2
            case .deletedDefaults: return 3
            }
        }
        return TemplateArchiveContents(
            stagingDir: stagingDir,
            manifest: manifest,
            items: items.sorted { order($0) < order($1) }
        )
    }

    private func readManifest(stagingDir: URL) throws -> TemplateArchiveManifest {
        let manifestURL = stagingDir.appending(path: TemplateArchiveExporter.manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw TemplateArchiveImportError.invalidManifest(
                "\(TemplateArchiveExporter.manifestFileName) is missing")
        }
        do {
            return try JSONDecoder().decode(
                TemplateArchiveManifest.self, from: Data(contentsOf: manifestURL))
        } catch let error as TemplateArchiveManifestError {
            switch error {
            case .newerSchema(let found, let supported):
                throw TemplateArchiveImportError.newerSchema(found: found, supported: supported)
            }
        } catch let error as DecodingError {
            throw TemplateArchiveImportError.invalidManifest(String(describing: error))
        } catch {
            throw TemplateArchiveImportError.invalidManifest(error.localizedDescription)
        }
    }

    private func attributedPaths(
        _ attribution: TemplateArchiveExporter, _ selection: TemplateArchiveSelection
    ) throws -> [String] {
        do {
            return try attribution.stagedRelativePaths(for: selection)
        } catch TemplateArchiveExportError.missingImageFile(let path) {
            throw TemplateArchiveImportError.missingImageFile(path)
        }
    }

    // MARK: - Conflicts

    // A conflict exists only when applying would overwrite a *local change* with
    // *different content*: pristine bundled state is overlaid silently, identical
    // content is a no-op.
    private func recordConflict<Record: Equatable>(
        archive: Record, local: Record?, bundledRecord: Record?
    ) -> Bool {
        guard let local else { return false }
        if local == archive { return false }
        if let bundledRecord, local == bundledRecord { return false }
        return true
    }

    private func fileConflict(files: Set<String>, stagingDir: URL) -> Bool {
        files.contains { relative in
            guard overrides.isContentOverridden(forRelative: relative) else { return false }
            guard let localURL = overrides.overrideURL(forRelative: relative),
                let localData = try? Data(contentsOf: localURL)
            else { return false }
            let archiveData = try? Data(contentsOf: stagingDir.appending(path: relative))
            return archiveData != localData
        }
    }

    private func templateConflict(
        _ template: TemplateDescriptor, files: Set<String>, stagingDir: URL
    ) -> Bool {
        if catalog.sharedComponent(id: template.id) != nil { return true }
        return recordConflict(
            archive: template,
            local: catalog.template(id: template.id),
            bundledRecord: bundled.template(id: template.id))
            || fileConflict(files: files, stagingDir: stagingDir)
    }

    private func componentConflict(
        _ component: SharedComponent, files: Set<String>, stagingDir: URL
    ) -> Bool {
        if catalog.template(id: component.id) != nil { return true }
        return recordConflict(
            archive: component,
            local: catalog.sharedComponent(id: component.id),
            bundledRecord: bundled.sharedComponent(id: component.id))
            || fileConflict(files: files, stagingDir: stagingDir)
    }

    private func baseConflict(_ base: BaseTemplate, files: Set<String>, stagingDir: URL) -> Bool {
        recordConflict(archive: base, local: catalog.base, bundledRecord: bundled.base)
            || fileConflict(files: files, stagingDir: stagingDir)
    }

    // MARK: - Apply side

    // All-or-nothing for the selected set: file copies are tracked and rolled
    // back (best effort) when the wirings or manifest save fails — the caller's
    // in-memory state only changes when this returns.
    func apply(
        _ contents: TemplateArchiveContents,
        selectedItemIDs: Set<String>,
        store: TemplateCatalogStore,
        hookWirings currentWirings: HookWiringStore,
        hookWiringsURL: URL?
    ) throws -> TemplateArchiveApplyResult {
        let selected = contents.items.filter { selectedItemIDs.contains($0.id) }
        let filesToCopy = Set(selected.flatMap(\.files)).sorted()

        var created: [String] = []
        var replaced: [(path: String, data: Data)] = []
        func rollbackFiles() {
            for entry in replaced {
                _ = try? overrides.writeOverride(entry.data, toRelative: entry.path)
            }
            for path in created { try? overrides.removeOverride(forRelative: path) }
        }

        do {
            for relative in filesToCopy {
                if overrides.hasOverride(forRelative: relative),
                    let existing = overrides.overrideURL(forRelative: relative)
                {
                    replaced.append((relative, try Data(contentsOf: existing)))
                } else {
                    created.append(relative)
                }
                let bytes = try Data(contentsOf: contents.stagingDir.appending(path: relative))
                try overrides.writeOverride(bytes, toRelative: relative)
            }
        } catch {
            rollbackFiles()
            throw error
        }

        var merged = catalog
        for item in selected {
            switch item.kind {
            case .base:
                if let base = contents.manifest.base { merged.base = base }
            case .template(let templateID):
                guard let record = contents.manifest.templates.first(where: { $0.id == templateID })
                else { continue }
                merged.deleteSharedComponent(id: templateID)
                if let index = merged.templates.firstIndex(where: { $0.id == templateID }) {
                    merged.templates[index] = record
                } else {
                    merged.templates.append(record)
                }
                ensureCategory(record.categoryID, in: &merged, manifest: contents.manifest)
            case .sharedComponent(let componentID):
                guard
                    let record = contents.manifest.sharedComponents.first(where: {
                        $0.id == componentID
                    })
                else { continue }
                merged.deleteTemplate(id: componentID)
                if let index = merged.sharedComponents.firstIndex(where: { $0.id == componentID }) {
                    merged.sharedComponents[index] = record
                } else {
                    merged.sharedComponents.append(record)
                }
            case .deletedDefaults:
                for tombstone in contents.manifest.tombstones {
                    applyTombstone(tombstone, to: &merged)
                }
            }
        }

        var newWirings = currentWirings
        let importedStems = TemplateArchiveExporter.hookStems(inPaths: filesToCopy)
        for wiring in contents.manifest.hookWirings where importedStems.contains(wiring.name) {
            newWirings.upsert(wiring)
        }
        if newWirings != currentWirings, let hookWiringsURL {
            do {
                try newWirings.save(to: hookWiringsURL)
            } catch {
                rollbackFiles()
                throw error
            }
        }

        do {
            try store.save(merged)
        } catch {
            rollbackFiles()
            if newWirings != currentWirings, let hookWiringsURL {
                try? currentWirings.save(to: hookWiringsURL)
            }
            throw error
        }
        return TemplateArchiveApplyResult(catalog: merged, hookWirings: newWirings)
    }

    // Categories are carrier metadata: created when missing so an imported
    // template lands in a named category, never overwriting a local rename.
    private func ensureCategory(
        _ categoryID: String, in merged: inout TemplateCatalog, manifest: TemplateArchiveManifest
    ) {
        guard merged.category(id: categoryID) == nil,
            let record = manifest.categories.first(where: { $0.id == categoryID })
        else { return }
        merged.categories.append(record)
    }

    private func applyTombstone(_ tombstone: Tombstone, to merged: inout TemplateCatalog) {
        switch tombstone.kind {
        case .template:
            merged.deleteTemplate(id: tombstone.id)
        case .sharedComponent:
            merged.deleteSharedComponent(id: tombstone.id)
        case .category:
            guard merged.templates(inCategory: tombstone.id).isEmpty else { return }
            merged.deleteCategory(id: tombstone.id)
        }
    }

    // Deleting a locally *modified* predefined item would lose those changes.
    private func tombstoneConflict(_ tombstones: [Tombstone]) -> Bool {
        tombstones.contains { tombstone in
            switch tombstone.kind {
            case .template:
                guard let local = catalog.template(id: tombstone.id) else { return false }
                return local != bundled.template(id: tombstone.id)
            case .sharedComponent:
                guard let local = catalog.sharedComponent(id: tombstone.id) else { return false }
                return local != bundled.sharedComponent(id: tombstone.id)
            case .category:
                guard let local = catalog.category(id: tombstone.id) else { return false }
                return local != bundled.category(id: tombstone.id)
            }
        }
    }
}
