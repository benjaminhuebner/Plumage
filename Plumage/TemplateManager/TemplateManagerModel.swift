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

    // The hierarchical content tree for the current selection (Base mirrors the
    // scaffolded output layout; templates/shared show their fragment files). Drives
    // the content column's outline. `contentFiles` is its flattened leaves, kept for
    // selection retention, add/import lookups and the ● marker set.
    private(set) var contentTree: [FileNode] = []
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

    // Relative paths of user hooks that still need wiring. Mirrored as observed state
    // (rebuilt on the event boundary, alongside `overriddenPaths`) so the ⚠ markers
    // don't stat the filesystem on every `OutlineGroup` row re-evaluation.
    private(set) var needsWiringPaths: Set<String> = []

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

    // A hook file the user just added/imported that has no wiring yet: presenting
    // this raises the wiring sheet. Also set by the "Edit wiring…" action.
    var pendingHookWiring: FileNode?

    // Transient sidebar editing state (mirrors `NavigatorModel.pendingCreate` /
    // `renaming`). A non-nil `categoryRename` puts that category's header into an
    // inline `TextField`; "New Category" creates the category then enters rename so
    // the user types its name immediately (the Finder new-folder idiom).
    var categoryRename: CategoryRename?

    // Drives the "New Template" sheet (name + image + starting point + category).
    var isAddingTemplate = false

    // Drives the "New Shared Component" sheet (name + kind + membership).
    var isAddingSharedComponent = false

    // A shared component awaiting a delete confirmation (the dialog names the
    // templates that currently include it).
    var pendingComponentDeletion: SharedComponent?

    // A custom (irreversible) template awaiting a delete confirmation. Predefined
    // templates delete straight away — they are restorable.
    var pendingTemplateDeletion: TemplateDescriptor?

    // Drives the "Restore Defaults" confirmation (resets structure to bundled,
    // keeps file-content overrides).
    var isConfirmingRestoreAll = false

    // A transient (~4 s) banner shown when a structural mutation fails to persist;
    // the in-memory catalog is rolled back to the last saved state (no half-applied
    // structure), and this explains why nothing changed.
    private(set) var structuralError: String?
    private var structuralErrorTask: Task<Void, Never>?

    private let store: TemplateCatalogStore
    let overrides: ScaffoldOverrides

    // Trigger metadata for user-authored hooks, persisted so a later scaffold wires
    // them into `settings.json`. Injectable for hermetic tests.
    private let hookWiringStoreURL: URL?
    private(set) var hookWirings: HookWiringStore

    init(
        store: TemplateCatalogStore = TemplateCatalogStore(),
        overrides: ScaffoldOverrides = .standard(bundledRoot: NewProjectAssets.bundledRoot),
        hookWiringStoreURL: URL? = nil
    ) {
        self.store = store
        self.overrides = overrides
        let storeURL = hookWiringStoreURL ?? (try? HookWiringStore.standardURL())
        self.hookWiringStoreURL = storeURL
        self.hookWirings = storeURL.flatMap { try? HookWiringStore.load(from: $0) } ?? HookWiringStore()
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
        contentTree = buildContentTree(for: selection)
        contentFiles = Self.flattenLeaves(contentTree)
        membership = membershipInfo(for: selection)
        refreshDerivedMarkers()
        // Retain the selection across a rebuild — including a selected *folder*, which
        // is not in `contentFiles` (leaves only) but is a real, selectable tree node.
        // Re-bind the fresh node instance so List selection keeps matching by value.
        if let current = selectedFile,
            let refreshed = Self.findNode(in: contentTree, relativePath: current.relativePath)
        {
            selectedFile = refreshed
            return
        }
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
        // A generated config has no bundled file — its read-only baseline is the
        // composer output, materialized to a temp file so the editor can seed from it.
        if let config = managerConfig(forRelative: file.relativePath) {
            editingFallbackURL = writeConfigPreview(generatedConfigContent(config), name: config.displayName)
            return
        }
        let bundled = overrides.bundledRoot.appending(path: file.relativePath)
        editingFallbackURL =
            FileManager.default.fileExists(atPath: bundled.path) ? bundled : nil
    }

    // Per-window scratch directory holding the generated-config baselines the editor
    // seeds from. Cleared with the window's process; never the override store.
    private let configPreviewRoot = FileManager.default.temporaryDirectory.appending(
        path: "PlumageConfigPreview-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func writeConfigPreview(_ content: String, name: String) -> URL? {
        try? FileManager.default.createDirectory(at: configPreviewRoot, withIntermediateDirectories: true)
        let url = configPreviewRoot.appending(path: name)
        guard (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
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
    // rather than Reset to Default. A generated config is never user-authored — it
    // has a generated baseline, so it resets (regenerates) rather than deletes.
    func isUserAuthored(_ file: FileNode) -> Bool {
        isUserAuthoredStore(file.relativePath)
    }

    // Store-path variant: a folder node carries its *output* path in `relativePath`, so
    // the move path resolves it to a store path first (`TemplateContentDropResolver`)
    // and checks authorship against that — never the output path.
    private func isUserAuthoredStore(_ storePath: String) -> Bool {
        if managerConfig(forRelative: storePath) != nil { return false }
        return !overrides.hasBundledOriginal(forRelative: storePath)
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
        // A per-file reset also lifts a tombstone on the same path, so resetting a file
        // that was moved away brings its bundled original back at this location.
        try? overrides.unsuppress(relativePath: relativePath)
        overriddenPaths.remove(relativePath)
        isEditorDirty = false
        editorReloadToken += 1
    }

    // A user-authored file pending a delete confirmation (a non-empty folder); the
    // view raises a confirmation dialog when this is set.
    var pendingDeleteConfirmation: FileNode?

    // Entry point for the Delete affordance: confirm first when the target is a
    // non-empty folder (e.g. a multi-file skill), otherwise delete straight away.
    func requestDelete(_ file: FileNode) {
        guard isUserAuthored(file) else { return }
        if requiresDeleteConfirmation(file) {
            pendingDeleteConfirmation = file
        } else {
            delete(file)
        }
    }

    func confirmPendingDelete() {
        guard let file = pendingDeleteConfirmation else { return }
        pendingDeleteConfirmation = nil
        delete(file)
    }

    // Trashing the whole skill tree (not just its SKILL.md) when the target is a
    // user skill directory warrants a confirmation. Flat single files don't.
    func requiresDeleteConfirmation(_ file: FileNode) -> Bool {
        guard isUserAuthored(file) else { return false }
        let target = deleteTarget(for: file)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir),
            isDir.boolValue
        else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []
        return contents.count > 1
    }

    // Delete a user-authored file: move its override to the Trash (recoverable) and
    // drop it from the tree. A user skill is a directory — trash the whole
    // `skills/<name>` tree, not just the selected file. A user hook drops its wiring
    // too, so the next scaffold removes it from settings.json as well. A no-op for
    // bundled-backed files (those reset, they don't delete).
    func delete(_ file: FileNode) {
        guard isUserAuthored(file) else { return }
        let target = deleteTarget(for: file)
        if let base = UserTemplateKind.hookBaseName(forRelativePath: file.relativePath) {
            hookWirings.remove(named: base)
            saveHookWirings()
        }
        _ = try? ClaudeProjectFiles.trashFile(at: target)
        overriddenPaths.remove(file.relativePath)
        if selectedFile == file {
            selectedFile = nil
            beginEditing(nil)
        }
        refreshContent()
    }

    // The override URL to trash for a file: a user skill is its whole `skills/<name>`
    // directory; everything else is the single override file.
    private func deleteTarget(for file: FileNode) -> URL {
        let fallback = overrides.overrideURL(forRelative: file.relativePath) ?? file.url
        guard let overrideRoot = overrides.overrideRoot else { return fallback }
        let components = file.relativePath.split(separator: "/")
        if components.count >= 2, components[0] == "skills" {
            return overrideRoot.appending(
                path: "skills/\(components[1])", directoryHint: .isDirectory)
        }
        return fallback
    }

    // MARK: - Hook wiring

    func isHook(_ file: FileNode) -> Bool {
        UserTemplateKind.hookBaseName(forRelativePath: file.relativePath) != nil
    }

    func wiring(forHook file: FileNode) -> HookWiring? {
        guard let base = UserTemplateKind.hookBaseName(forRelativePath: file.relativePath)
        else { return nil }
        return hookWirings.wiring(named: base)
    }

    // Only USER-authored hooks are flagged: bundled hooks are wired by `SettingsComposer`'s
    // built-in table, so an unwired one there would be a real mistake. Reads the cached set
    // so a row render never touches disk (see `refreshDerivedMarkers`).
    func needsWiring(_ file: FileNode) -> Bool { needsWiringPaths.contains(file.relativePath) }

    // Uncached (touches disk via `isUserAuthored`); only for building `needsWiringPaths`
    // on an event boundary, never from `body`.
    private func computeNeedsWiring(_ file: FileNode) -> Bool {
        isHook(file) && isUserAuthored(file) && wiring(forHook: file) == nil
    }

    func saveWiring(forHook file: FileNode, event: HookEvent, matcher: String?) {
        guard let base = UserTemplateKind.hookBaseName(forRelativePath: file.relativePath)
        else { return }
        let trimmed = matcher?.trimmingCharacters(in: .whitespacesAndNewlines)
        hookWirings.upsert(
            HookWiring(
                name: base, event: event, matcher: (trimmed?.isEmpty ?? true) ? nil : trimmed))
        saveHookWirings()
        // The hook is now wired — clear its ⚠ marker without a full disk rescan.
        needsWiringPaths.remove(relativePath(for: .hook, file: base))
    }

    // Creates the store directory first so a save before any other write lands
    // cleanly (mirrors `TemplatesSettingsModel`).
    private func saveHookWirings() {
        guard let url = hookWiringStoreURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? hookWirings.save(to: url)
    }

    // The only place that touches disk for marker state — runs on the event boundary
    // (load, selection change, add/import/delete) so `body`/row renders stay disk-free.
    private func refreshDerivedMarkers() {
        overriddenPaths = Set(
            contentFiles.map(\.relativePath).filter {
                overrides.isContentOverridden(forRelative: $0)
            })
        needsWiringPaths = Set(contentFiles.filter(computeNeedsWiring).map(\.relativePath))
    }

    // MARK: - Drag-and-drop import

    // A transient (~3 s) banner for a rejected or partial Finder drop, mirroring the
    // Navigator's drop-reject feedback.
    private(set) var dropBanner: String?
    private var dropBannerTask: Task<Void, Never>?

    private func showDropBanner(_ message: String) {
        dropBannerTask?.cancel()
        dropBanner = message
        dropBannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dropBanner = nil
        }
    }

    // Import Finder files/folders into the selected tree folder, copying them (the
    // source stays) with suffix-on-collision and containment validation. Any file or
    // folder is accepted; a dropped folder with a top-level `SKILL.md` is treated as a
    // skill (routed to `skills/`) so it scaffolds correctly. A failed copy is surfaced
    // in a banner. Returns whether anything was imported.
    @discardableResult
    func importDropped(urls: [URL], into target: FileNode? = nil) -> Bool {
        guard let overrideRoot = overrides.overrideRoot else {
            showDropBanner("No override store is available.")
            return false
        }
        let targetDir = addTargetStorageDir(for: target)
        let fileManager = FileManager.default
        var first: (storage: String, isDirectory: Bool)?
        var importedStoragePaths: Set<String> = []
        var rejected: [String] = []
        for url in urls {
            guard let plan = Self.dropPlan(for: url, targetDir: targetDir) else {
                rejected.append(url.lastPathComponent)
                continue
            }
            // A standalone `.sh` dropped onto a Shared Component joins it as a hook,
            // which the membership and the scaffolder both resolve at `hooks/<name>.sh`
            // — so its bytes must land there, not in the component's selected folder.
            // Outside a component a dropped file stays verbatim in the target folder.
            let joinsComponentAsHook =
                !plan.isDirectory && !plan.isSkill && plan.name.hasSuffix(".sh")
                && membershipComponentID(forKind: .hook) != nil
            // A skill is a scope-owned loose folder under `<root>/skills` (#00078); a hook
            // joining a component stays global; everything else uses the scoped target dir.
            let directory: String
            if joinsComponentAsHook {
                directory = "hooks"
            } else if plan.isSkill {
                let root = activeScope.storageRoot
                directory = root.isEmpty ? "skills" : "\(root)/skills"
            } else {
                directory = plan.directory
            }
            let parent =
                directory.isEmpty
                ? overrideRoot : overrideRoot.appending(path: directory, directoryHint: .isDirectory)
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                let target = try ClaudeProjectFiles.findFreeName(in: parent, base: plan.name)
                guard target.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/")
                else {
                    rejected.append(url.lastPathComponent)
                    continue
                }
                try fileManager.copyItem(at: url, to: target)
                let leaf = target.lastPathComponent
                let dir = directory.isEmpty ? "" : "\(directory)/"
                let storage = plan.isSkill ? "\(dir)\(leaf)/SKILL.md" : "\(dir)\(leaf)"
                importedStoragePaths.insert(storage)
                if first == nil { first = (storage, plan.isDirectory && !plan.isSkill) }
                // Dropping a `.sh` onto a component joins it as a hook (the only
                // membership-backed kind); a dropped skill is now a scope-owned folder.
                let importKind: UserTemplateKind? = joinsComponentAsHook ? .hook : nil
                if let importKind, let componentKind = Self.sharedComponentKind(for: importKind),
                    let componentID = membershipComponentID(forKind: importKind)
                {
                    registerMembership(
                        componentID, kind: componentKind,
                        fileName: importKind == .hook ? String(leaf.dropLast(3)) : leaf)
                }
            } catch {
                rejected.append(url.lastPathComponent)
            }
        }
        refreshContent()
        selectImported(first)
        // An imported hook still needs wiring: raise the sheet for the first unwired one.
        if let hookNode = contentFiles.first(where: { node in
            node.relativePath.hasPrefix("hooks/") && importedStoragePaths.contains(node.relativePath)
                && needsWiring(node)
        }) {
            pendingHookWiring = hookNode
        }
        if !rejected.isEmpty {
            showDropBanner("Can't import: \(rejected.joined(separator: ", "))")
        }
        return first != nil
    }

    private func selectImported(_ first: (storage: String, isDirectory: Bool)?) {
        guard let first else { return }
        let node: FileNode?
        if first.isDirectory {
            node = Self.outputPath(forStorageDir: first.storage, scope: activeScope)
                .flatMap { Self.findNode(in: contentTree, relativePath: $0) }
        } else {
            node = contentFiles.first { $0.relativePath == first.storage }
        }
        if let node {
            selectedFile = node
            beginEditing(node)
        }
    }

    // Plans a dropped URL: a folder with a top-level `SKILL.md` routes to `skills/`
    // (so it is recognized as a skill); every other file or folder lands verbatim in
    // the drop target directory. Returns nil only when the URL does not exist.
    private static func dropPlan(
        for url: URL, targetDir: String
    )
        -> (directory: String, name: String, isSkill: Bool, isDirectory: Bool)?
    {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue, fileManager.fileExists(atPath: url.appending(path: "SKILL.md").path) {
            return ("skills", url.lastPathComponent, true, true)
        }
        return (targetDir, url.lastPathComponent, false, isDir.boolValue)
    }

    // MARK: - Internal move (drag within the content tree)

    // Move dropped tree nodes into `target`'s folder. A user-authored item is physically
    // relocated inside the override store; a bundled / override-of-bundled item can't move
    // in place and takes the tombstone path (Workstream B). Selection follows the first
    // successfully moved item to its new path. A drop onto an item's own folder, or a
    // folder into its own subtree, is skipped.
    func moveNodes(_ sources: [FileNode], into target: FileNode) {
        guard let overrideRoot = overrides.overrideRoot else {
            showDropBanner("No override store is available.")
            return
        }
        guard let targetDir = TemplateContentDropResolver.targetStoreDir(for: target, scope: activeScope)
        else {
            showDropBanner("Can't move here.")
            return
        }
        var movedSelection: (storage: String, isDirectory: Bool)?
        var rejected: [String] = []
        for source in sources {
            let sourceStorePath = TemplateContentDropResolver.storePath(for: source, scope: activeScope)
            guard
                !TemplateContentDropResolver.rejectsMove(
                    storePath: sourceStorePath, intoStoreDir: targetDir)
            else { continue }
            let moved =
                isUserAuthoredStore(sourceStorePath)
                ? moveUserAuthored(
                    storePath: sourceStorePath, isDirectory: source.isDirectory,
                    intoStoreDir: targetDir, overrideRoot: overrideRoot)
                : moveBundled(
                    storePath: sourceStorePath, isDirectory: source.isDirectory,
                    intoStoreDir: targetDir, overrideRoot: overrideRoot)
            if let moved {
                if movedSelection == nil { movedSelection = moved }
            } else {
                rejected.append(source.name)
            }
        }
        refreshContent()
        selectImported(movedSelection)
        if !rejected.isEmpty {
            showDropBanner("Can't move: \(rejected.joined(separator: ", "))")
        }
    }

    // Physically relocate a user-authored override file/folder to `targetDir`, returning
    // its new store path (and directory-ness) for selection, or nil if it is missing on
    // disk or the move fails. Suffix-walks on a name collision and carries hook wiring.
    private func moveUserAuthored(
        storePath: String, isDirectory: Bool, intoStoreDir targetDir: String, overrideRoot: URL
    ) -> (storage: String, isDirectory: Bool)? {
        let sourceURL = overrideRoot.appending(path: storePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let targetFolderURL =
            targetDir.isEmpty
            ? overrideRoot : overrideRoot.appending(path: targetDir, directoryHint: .isDirectory)
        guard let movedURL = try? ClaudeProjectFiles.moveItem(at: sourceURL, to: targetFolderURL)
        else { return nil }
        let leaf = movedURL.lastPathComponent
        let newStorePath = targetDir.isEmpty ? leaf : "\(targetDir)/\(leaf)"
        followHookWiring(from: storePath, to: newStorePath)
        overriddenPaths.remove(storePath)
        return (newStorePath, isDirectory)
    }

    // Move a bundled (or override-of-bundled) file: it can't be relocated in place —
    // its bytes live in the read-only app bundle — so its effective content is
    // materialized as an override at the destination and the source path is tombstoned
    // (suppressed) so it stops appearing at its old position. Any stale override and
    // user wiring at the source are dropped. Bundled directories are out of scope.
    private func moveBundled(
        storePath: String, isDirectory: Bool, intoStoreDir targetDir: String, overrideRoot: URL
    ) -> (storage: String, isDirectory: Bool)? {
        guard !isDirectory else { return nil }
        guard let data = try? Data(contentsOf: overrides.url(forRelative: storePath)) else {
            return nil
        }
        let targetFolderURL =
            targetDir.isEmpty
            ? overrideRoot : overrideRoot.appending(path: targetDir, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
        let baseName = (storePath as NSString).lastPathComponent
        guard let freeURL = try? ClaudeProjectFiles.findFreeName(in: targetFolderURL, base: baseName)
        else { return nil }
        let leaf = freeURL.lastPathComponent
        let newStorePath = targetDir.isEmpty ? leaf : "\(targetDir)/\(leaf)"
        guard (try? overrides.writeOverride(data, toRelative: newStorePath)) != nil else { return nil }
        try? overrides.suppress(relativePath: storePath)
        try? overrides.removeOverride(forRelative: storePath)  // drop any stale override now at B
        if let base = UserTemplateKind.hookBaseName(forRelativePath: storePath) {
            hookWirings.remove(named: base)
            saveHookWirings()
        }
        overriddenPaths.remove(storePath)
        return (newStorePath, isDirectory)
    }

    // Keep hook wiring consistent after a move: a hook that leaves `hooks/` loses its
    // function, so its wiring is dropped (as on delete); a collision-renamed hook keeps
    // its wiring under the new base name.
    private func followHookWiring(from oldStorePath: String, to newStorePath: String) {
        guard let oldBase = UserTemplateKind.hookBaseName(forRelativePath: oldStorePath),
            let existing = hookWirings.wiring(named: oldBase)
        else { return }
        let newBase = UserTemplateKind.hookBaseName(forRelativePath: newStorePath)
        if newBase == oldBase { return }  // moved within hooks/, same name — wiring stands
        hookWirings.remove(named: oldBase)
        if let newBase {
            hookWirings.upsert(
                HookWiring(name: newBase, event: existing.event, matcher: existing.matcher))
        }
        saveHookWirings()
    }

    // MARK: - Add

    // The kinds the user can author — available in every selection, since the content
    // tree is a file manager for Base, Templates and Shared Components alike. Loose
    // kinds (doc/agent/skill/file/folder) are owned by the active tier's subtree
    // (#00078); a `.hook` is the one composition asset and joins the selected
    // component's membership instead of being scope-owned.
    var addableKinds: [UserTemplateKind] {
        [.hook, .skill, .doc, .agent, .file, .folder]
    }

    // The composition component kind a `UserTemplateKind` joins by manifest membership.
    // Only `.hook` qualifies: it feeds `effectiveHooks` and stays a global, membership-
    // tracked asset. Skills and everything else are now scope-owned loose files on disk
    // (no membership) — legacy `.skill` memberships still decode, just aren't created.
    static func sharedComponentKind(for kind: UserTemplateKind) -> SharedComponentKind? {
        switch kind {
        case .hook: return .hook
        default: return nil
        }
    }

    // The selected component a hook add or drop should join (the only membership-backed
    // kind; loose kinds are owned by the component's `components/<id>/` subtree instead).
    private func membershipComponentID(forKind kind: UserTemplateKind) -> String? {
        guard case .sharedComponent(let id) = selection,
            catalog.sharedComponent(id: id) != nil,
            Self.sharedComponentKind(for: kind) != nil
        else { return nil }
        return id
    }

    // The tier that owns loose files authored in the current selection (#00078).
    var activeScope: ManagerScope { selection.map(ManagerScope.scope(for:)) ?? .base }

    private func registerMembership(
        _ componentID: String?, kind: SharedComponentKind, fileName: String
    ) {
        guard let componentID else { return }
        var updated = catalog
        updated.addFile(toComponentID: componentID, kind: kind, fileName: fileName)
        persist(updated)
    }

    // The override-store directory a new/dropped item lands in: the given node (a
    // dropped-on row) or the current selection — a folder targets itself, a file its
    // parent, and nothing selected the active tier's scope root (#00078). A file leaf's
    // `relativePath` is already a scoped store path; a folder's is an output path mapped
    // back through the active scope. A selected node *outside* the active scope subtree
    // (e.g. a component's layer `CLAUDE.md` under `templates/<layer>`, or a global
    // config) would pull a new loose item out of its tier — so the result is clamped
    // back to the scope root, keeping loose files where they belong.
    func addTargetStorageDir(for node: FileNode? = nil) -> String {
        let root = activeScope.storageRoot
        guard let ref = node ?? selectedFile else { return root }
        let dir =
            ref.isDirectory
            ? Self.storageDir(forOutputFolder: ref.relativePath, scope: activeScope)
            : (ref.relativePath as NSString).deletingLastPathComponent
        guard !root.isEmpty else { return dir }
        return (dir == root || dir.hasPrefix(root + "/")) ? dir : root
    }

    // The content-tree node carrying `url` (a folder's synthetic output URL or a file
    // leaf's resolved override/bundled URL), used to map a drag payload back to its node.
    func contentNode(forURL url: URL) -> FileNode? {
        let target = url.standardizedFileURL.path
        func search(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.url.standardizedFileURL.path == target { return node }
                if let children = node.children, let found = search(children) { return found }
            }
            return nil
        }
        return search(contentTree)
    }

    // Author a new override item of `kind`, seeded with its starter, suffix-walking on
    // collision and validating containment via `ClaudeProjectFiles`. The new item is
    // selected. Returns the created node (so a hook add can raise the wiring sheet), or
    // nil on an invalid name / no override store / write failure.
    @discardableResult
    func addUserFile(kind: UserTemplateKind, rawName: String) -> FileNode? {
        guard let name = UserTemplateKind.sanitizedName(from: rawName),
            let overrideRoot = overrides.overrideRoot
        else { return nil }
        // The content tree is a file manager: when a folder is selected, every kind is
        // created inside it (what the user asked for). With no folder selected the kind
        // falls back to its sensible home — a typed kind to its canonical dir within the
        // scope (so docs/skills/agents stay functional by default), a typeless one to the
        // scope root. A hook is always the global `hooks/` composition asset (+ wiring).
        let scope = activeScope
        let componentID = membershipComponentID(forKind: kind)
        let baseDir: String
        if kind == .hook {
            baseDir = kind.directory
        } else if let selected = selectedFile, selected.isDirectory {
            baseDir = addTargetStorageDir()
        } else if kind.usesTargetDirectory {
            baseDir = scope.storageRoot
        } else {
            baseDir = scope.storageRoot.isEmpty ? kind.directory : "\(scope.storageRoot)/\(kind.directory)"
        }
        let parent =
            baseDir.isEmpty
            ? overrideRoot : overrideRoot.appending(path: baseDir, directoryHint: .isDirectory)
        func storagePath(_ leaf: String) -> String { baseDir.isEmpty ? leaf : "\(baseDir)/\(leaf)" }
        do {
            switch kind {
            case .skill:
                let dir = try ClaudeProjectFiles.createFolderAt(parent: parent, name: name)
                try kind.starter(forLeaf: dir.lastPathComponent).write(
                    to: dir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
                return selectCreatedFile(storagePath: storagePath("\(dir.lastPathComponent)/SKILL.md"), kind: kind)
            case .folder:
                let dir = try ClaudeProjectFiles.createFolderAt(parent: parent, name: name)
                refreshContent()
                let node = Self.outputPath(forStorageDir: storagePath(dir.lastPathComponent), scope: scope)
                    .flatMap { Self.findNode(in: contentTree, relativePath: $0) }
                selectedFile = node
                beginEditing(node)
                return node
            default:
                let url = try ClaudeProjectFiles.createFileAt(
                    parent: parent, name: kind.fileName(forSanitized: name))
                try kind.starter(forLeaf: url.lastPathComponent).write(
                    to: url, atomically: true, encoding: .utf8)
                // A hook joining a component is registered by its base name (no `.sh`).
                if kind == .hook {
                    registerMembership(
                        componentID, kind: .hook, fileName: String(url.lastPathComponent.dropLast(3)))
                }
                return selectCreatedFile(storagePath: storagePath(url.lastPathComponent), kind: kind)
            }
        } catch {
            return nil
        }
    }

    private func selectCreatedFile(storagePath: String, kind: UserTemplateKind) -> FileNode? {
        refreshContent()
        let node = contentFiles.first { $0.relativePath == storagePath }
        if let node {
            selectedFile = node
            beginEditing(node)
            // Adding a hook raises the wiring sheet so it does not scaffold inert.
            if kind == .hook { pendingHookWiring = node }
        }
        return node
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

    // The override relative path a shared component's file resolves to, by kind.
    func relativePath(for kind: SharedComponentKind, file: String) -> String {
        switch kind {
        case .layer: ScaffoldOverrides.layerRelativePath(file)
        case .hook: "hooks/\(file).sh"
        case .skill: "skills/\(file)/SKILL.md"
        case .config: "configs/\(file)"
        }
    }

    // A referenced file missing on disk is omitted from the tree (the code view
    // then shows a placeholder rather than crashing — see the edge cases).
    func fileNode(relative: String, displayName: String? = nil) -> FileNode? {
        let url = overrides.url(forRelative: relative)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return FileNode(
            url: url, relativePath: relative,
            name: displayName ?? (relative as NSString).lastPathComponent,
            isDirectory: false, children: nil)
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

// Inline-rename session for a sidebar category header. `id` is the category id;
// `name` is bound by the header's `TextField`.
struct CategoryRename: Identifiable, Equatable {
    let id: String
    var name: String
}

// A deleted predefined item offered in the Restore menu.
struct RestorableItem: Identifiable, Hashable {
    let kind: TombstoneKind
    let itemID: String
    let name: String

    var id: String { "\(kind):\(itemID)" }

    var menuLabel: String {
        let noun =
            switch kind {
            case .category: "Category"
            case .template: "Template"
            case .sharedComponent: "Shared Component"
            }
        return "\(name) (\(noun))"
    }
}

// MARK: - Structural editing (categories)

extension TemplateManagerModel {
    // Creates a category, persists it, then enters inline rename so the user names
    // it right away. A persist failure rolls back and skips rename.
    func beginAddCategory() {
        var updated = catalog
        let created = updated.addCategory(name: "New Category")
        guard persist(updated) else { return }
        categoryRename = CategoryRename(id: created.id, name: created.name)
    }

    func beginRenameCategory(id: String) {
        guard let category = catalog.category(id: id) else { return }
        categoryRename = CategoryRename(id: id, name: category.name)
    }

    func cancelCategoryRename() { categoryRename = nil }

    func commitCategoryRename() {
        guard let rename = categoryRename else { return }
        categoryRename = nil
        var updated = catalog
        updated.renameCategory(id: rename.id, to: rename.name)
        guard updated != catalog else { return }
        persist(updated)
    }

    // Block-until-empty: never silently orphan a category's templates (spec edge
    // case default). The user moves or deletes them first.
    func canDeleteCategory(id: String) -> Bool {
        catalog.templates(inCategory: id).isEmpty
    }

    func deleteCategory(id: String) {
        guard canDeleteCategory(id: id) else {
            showStructuralError("Move or delete this category's templates before deleting it.")
            return
        }
        var updated = catalog
        updated.deleteCategory(id: id)
        persist(updated)
    }

    func moveCategory(id: String, by offset: Int) {
        var ids = catalog.sortedCategories.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        var updated = catalog
        updated.reorderCategories(ids)
        persist(updated)
    }

    // MARK: - Template placement

    func moveTemplate(id: String, toCategory categoryID: String) {
        guard catalog.template(id: id)?.categoryID != categoryID else { return }
        var updated = catalog
        updated.moveTemplate(id: id, toCategory: categoryID)
        persist(updated)
    }

    func moveTemplate(id: String, withinCategoryBy offset: Int) {
        guard let template = catalog.template(id: id) else { return }
        var ids = catalog.templates(inCategory: template.categoryID).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        var updated = catalog
        updated.reorderTemplates(inCategory: template.categoryID, orderedIDs: ids)
        persist(updated)
    }

    // MARK: - Template authoring

    // Resolves a `TemplateImage.file` relative path to its on-disk URL (override
    // store) so `TemplateImageView` can render the imported image.
    func imageFileURL(forRelative relativePath: String) -> URL? {
        let url = overrides.url(forRelative: relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Creates a custom template: builds the descriptor, copies any imported image
    // into the override store, writes the template's own layer file (so it appears
    // and is editable), then persists. Selects the new template on success.
    @discardableResult
    func addTemplate(_ request: NewTemplateRequest) -> Bool {
        guard overrides.overrideRoot != nil else {
            showStructuralError("No override store is available to author a template.")
            return false
        }
        var updated = catalog
        let descriptor = updated.addTemplate(
            name: request.name, image: .symbol("doc"), categoryID: request.categoryID,
            startingFrom: request.startingPoint)
        let id = descriptor.id

        let image: TemplateImage
        switch request.imageChoice {
        case .symbol(let name):
            image = .symbol(name)
        case .importedFile(let url):
            guard let relativePath = copyTemplateImage(from: url, templateID: id) else {
                showStructuralError("Couldn't import the chosen image.")
                return false
            }
            image = .file(relativePath)
        }
        if let index = updated.templates.firstIndex(where: { $0.id == id }) {
            updated.templates[index].image = image
        }

        writeOwnLayer(forTemplate: descriptor, startingFrom: request.startingPoint)

        guard persist(updated) else { return false }
        selection = .template(id)
        refreshContent()
        return true
    }

    private func copyTemplateImage(from source: URL, templateID: String) -> String? {
        guard let overrideRoot = overrides.overrideRoot else { return nil }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let relativePath = "template-images/\(templateID).\(ext)"
        let destination = overrideRoot.appending(path: relativePath)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            return relativePath
        } catch {
            return nil
        }
    }

    // Seeds the template's own layer file. `.empty` gets a heading starter; `.copy`
    // concatenates the source template's own layer content so the user starts from
    // the same text and edits from there.
    private func writeOwnLayer(forTemplate descriptor: TemplateDescriptor, startingFrom: TemplateStartingPoint) {
        let relativePath = ScaffoldOverrides.layerRelativePath(descriptor.id)
        var content = "# \(descriptor.name)\n"
        if case .copy(let sourceID) = startingFrom, let source = catalog.template(id: sourceID) {
            let copied = source.templateLayers
                .compactMap { try? overrides.string(atRelative: ScaffoldOverrides.layerRelativePath($0)) }
                .joined(separator: "\n\n")
            if !copied.isEmpty { content = copied }
        }
        _ = try? overrides.writeOverride(content, toRelative: relativePath)
    }

    // MARK: - Shared-component membership & authoring

    // The component being edited, when a shared component is selected — drives the
    // membership checklist in the middle column.
    var editingComponentID: String? {
        if case .sharedComponent(let id) = selection { return id }
        return nil
    }

    func isUserAuthoredComponent(id: String) -> Bool {
        !catalog.isPredefinedSharedComponent(id)
    }

    func isMember(componentID: String, templateID: String) -> Bool {
        catalog.sharedComponent(id: componentID)?.isMember(templateID) ?? false
    }

    func setMembership(componentID: String, templateID: String, isMember: Bool) {
        var updated = catalog
        updated.setMembership(componentID: componentID, templateID: templateID, isMember: isMember)
        guard updated != catalog else { return }
        persist(updated)
    }

    @discardableResult
    func addSharedComponent(_ request: NewSharedComponentRequest) -> Bool {
        guard overrides.overrideRoot != nil else {
            showStructuralError("No override store is available to author a component.")
            return false
        }
        var updated = catalog
        let component = updated.addSharedComponent(
            name: request.name, kind: request.kind, memberTemplateIDs: request.memberTemplateIDs)
        writeComponentStarter(for: component)
        guard persist(updated) else { return false }
        selection = .sharedComponent(component.id)
        refreshContent()
        return true
    }

    // The dialog always confirms (it names the affected templates); the actual
    // delete drops the manifest record and trashes the component's own override
    // files (predefined bundled files are never trashed).
    func requestDeleteSharedComponent(id: String) {
        guard let component = catalog.sharedComponent(id: id) else { return }
        pendingComponentDeletion = component
    }

    func confirmDeleteSharedComponent() {
        guard let component = pendingComponentDeletion else { return }
        pendingComponentDeletion = nil
        var updated = catalog
        updated.deleteSharedComponent(id: component.id)
        for file in component.files {
            let relativePath = relativePath(for: file.kind, file: file.name)
            if !overrides.hasBundledOriginal(forRelative: relativePath),
                let url = overrides.overrideURL(forRelative: relativePath)
            {
                _ = try? ClaudeProjectFiles.trashFile(at: url)
            }
        }
        if selection == .sharedComponent(component.id) { selection = .base }
        persist(updated)
        refreshContent()
    }

    private func writeComponentStarter(for component: SharedComponent) {
        guard let file = component.files.first else { return }
        let relativePath = relativePath(for: file.kind, file: file.name)
        let content: String
        switch file.kind {
        case .layer: content = "# \(component.name)\n"
        case .hook: content = "#!/bin/bash\n# \(component.name)\n"
        case .skill: content = "# \(component.name)\n"
        case .config: content = "{}\n"
        }
        _ = try? overrides.writeOverride(content, toRelative: relativePath)
    }

    // MARK: - Delete templates

    func deleteTemplate(id: String) {
        guard let template = catalog.template(id: id) else { return }
        if catalog.isPredefinedTemplate(id) {
            performDeleteTemplate(template)
        } else {
            pendingTemplateDeletion = template
        }
    }

    func confirmDeleteTemplate() {
        guard let template = pendingTemplateDeletion else { return }
        pendingTemplateDeletion = nil
        performDeleteTemplate(template)
    }

    private func performDeleteTemplate(_ template: TemplateDescriptor) {
        var updated = catalog
        updated.deleteTemplate(id: template.id)
        if !catalog.isPredefinedTemplate(template.id) {
            trashTemplateOverrides(template)
        }
        if selection == .template(template.id) { selection = .base }
        persist(updated)
        refreshContent()
    }

    // Bundled-backed paths are left alone — predefined deletes tombstone instead, so a
    // content-override survives for restore. Only a custom template's own files go.
    private func trashTemplateOverrides(_ template: TemplateDescriptor) {
        var paths = template.templateLayers.map(ScaffoldOverrides.layerRelativePath)
        if case .file(let imagePath) = template.image { paths.append(imagePath) }
        for relativePath in paths where !overrides.hasBundledOriginal(forRelative: relativePath) {
            if let url = overrides.overrideURL(forRelative: relativePath) {
                _ = try? ClaudeProjectFiles.trashFile(at: url)
            }
        }
    }

    // MARK: - Restore

    // Bundled predefined items the user deleted, for the per-item Restore menu.
    var restorableItems: [RestorableItem] {
        catalog.deletedPredefinedItems().map {
            RestorableItem(kind: $0.kind, itemID: $0.id, name: $0.name)
        }
    }

    func restore(_ item: RestorableItem) {
        var updated = catalog
        updated.restore(item.kind, id: item.itemID)
        guard persist(updated) else { return }
        switch item.kind {
        case .template: selection = .template(item.itemID)
        case .sharedComponent: selection = .sharedComponent(item.itemID)
        case .category: break
        }
        refreshContent()
    }

    // Resets the catalog structure to the bundled baseline (drops the overlay:
    // catalog tombstones, custom items, reorders, membership overrides) and lifts every
    // file tombstone, so a bundled file the user moved away reappears at its original
    // path. File-content overrides are a separate store and are deliberately kept (so an
    // edit — including the moved copy materialized at its new path — survives).
    func restoreAllDefaults() {
        do {
            try store.reset()
            overrides.clearTombstones()
            catalog = store.load()
            selection = .base
            refreshContent()
        } catch {
            showStructuralError(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    // Applies `updated` in memory, then persists the derived overlay. On a write
    // failure the in-memory catalog rolls back and a banner explains why — the
    // window never shows structure that isn't on disk.
    @discardableResult
    func persist(_ updated: TemplateCatalog) -> Bool {
        let previous = catalog
        catalog = updated
        do {
            try store.save(updated)
            return true
        } catch {
            catalog = previous
            showStructuralError(error.localizedDescription)
            return false
        }
    }

    private func showStructuralError(_ message: String) {
        structuralErrorTask?.cancel()
        structuralError = message
        structuralErrorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.structuralError = nil
        }
    }
}
