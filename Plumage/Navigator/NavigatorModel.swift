import Foundation

@MainActor
@Observable
final class NavigatorModel {
    // Unified file tree state. Built off-Main from `FileTreeBuilder.build(...)`
    // on every reload.
    private(set) var rootNodes: [FileNode] = []
    private(set) var loadError: String?

    // Transient sidebar state for the "+ creates a new row with a focused
    // TextField" interaction. View binds the textfield to `pendingCreate?.name`
    // and calls commit/cancel based on Enter/Escape/blur.
    var pendingCreate: PendingCreate?

    // Inline rename of an existing row. Set when the user hits Enter or
    // picks "Rename" from the context menu; cleared on commit/cancel.
    var renaming: RenameSession?

    // ~3 s transient banner that surfaces drop/inline rejections in the
    // status bar. Mutators always set + auto-reset via `bannerResetTask`.
    private(set) var dropRejectMessage: String?
    // Path remappings emitted by the most recent rename/move/trash so the
    // window can keep the selected detail in sync (spec: "Detail-Pane folgt"
    // on move, falls back to .kanban on trash). Observed via onChange.
    private(set) var routeRewrites: [RouteRewrite] = []

    // Move/remove rewrites derived from the inode diff of the most recent
    // reload — i.e. *external* (FSEvents) renames, moves and deletes the
    // in-app mutators never emitted as `routeRewrites`. The pin watcher applies
    // these so an externally renamed pinned file follows instead of vanishing.
    private(set) var externalRewrites: [RouteRewrite] = []

    private var bannerResetTask: Task<Void, Never>?
    private let bannerDisplayDuration: Duration
    // Monotonic token so a slow `FileTreeBuilder.build` from an earlier
    // reload can't overwrite the tree a newer reload already published.
    private var reloadGeneration = 0
    // path→inode snapshot of the previous reload, plus the project it described.
    // A reload of a *different* project resets the baseline so the first diff
    // doesn't mistake another project's files for deletions.
    private var fileInodes: [String: Int] = [:]
    private var inodeBaselineProject: URL?

    init(bannerDisplayDuration: Duration = .seconds(3)) {
        self.bannerDisplayDuration = bannerDisplayDuration
    }

    func reload(projectURL: URL) async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let result = await Task.detached(priority: .userInitiated) {
            () -> (nodes: [FileNode], index: FileTreeBuilder.FileIndex) in
            let nodes = FileTreeBuilder.build(projectURL: projectURL)
            return (nodes, FileTreeBuilder.fileIndex(in: nodes))
        }.value
        // A newer reload started while this build ran — its result is fresher,
        // so drop ours instead of clobbering it with stale nodes.
        guard generation == reloadGeneration else { return }
        self.rootNodes = result.nodes
        // Diff against the previous reload's inodes — but only within the same
        // project; a project switch starts a fresh baseline (no spurious diff).
        let sameProject = inodeBaselineProject == projectURL
        externalRewrites =
            sameProject
            ? Self.deriveExternalRewrites(
                previousInodes: fileInodes,
                currentInodes: result.index.inodes,
                currentPaths: result.index.paths)
            : []
        fileInodes = result.index.inodes
        inodeBaselineProject = projectURL
        // `pendingCreate` is intentionally preserved across reloads — an
        // FSEvent triggered mid-inline-edit must not collapse the user's
        // open create row.
    }

    // Pure inode diff: a previously-known path that is gone from `currentPaths`
    // becomes `.moved` if a *new* path now carries its inode (rename/move on the
    // same volume preserves the inode), otherwise `.removed`. Files that merely
    // appeared, or were edited in place (same path), produce nothing. Emitted in
    // sorted old-path order for determinism. Inode reuse within a single reload
    // window can mis-pair a delete+create as a move — accepted, since the
    // fallback severity (a pin pointing at a new file) matches the prior "drop".
    nonisolated static func deriveExternalRewrites(
        previousInodes: [String: Int],
        currentInodes: [String: Int],
        currentPaths: Set<String>
    ) -> [RouteRewrite] {
        guard !previousInodes.isEmpty else { return [] }
        var currentPathByInode: [Int: String] = [:]
        for (path, ino) in currentInodes { currentPathByInode[ino] = path }
        var rewrites: [RouteRewrite] = []
        for oldPath in previousInodes.keys.sorted() where !currentPaths.contains(oldPath) {
            guard let ino = previousInodes[oldPath] else { continue }
            if let newPath = currentPathByInode[ino], previousInodes[newPath] == nil {
                rewrites.append(.moved(oldRelativePath: oldPath, newRelativePath: newPath))
            } else {
                rewrites.append(.removed(oldRelativePath: oldPath))
            }
        }
        return rewrites
    }

    func beginPendingCreate(parent: URL, isFolder: Bool) {
        pendingCreate = PendingCreate(
            section: .treeNode(parent: parent, isFolder: isFolder),
            name: PendingCreate.Section.treeNode(parent: parent, isFolder: isFolder).defaultName
        )
    }

    func cancelPendingCreate() {
        pendingCreate = nil
    }

    func isPendingCreate(at section: PendingCreate.Section) -> Bool {
        pendingCreate?.section == section
    }

    @discardableResult
    func commitPendingCreate(projectURL: URL) async -> NavigatorRoute? {
        guard let pending = pendingCreate else { return nil }
        let trimmed = pending.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                () -> URL in
                switch pending.section {
                case .treeNode(let parent, let isFolder):
                    if isFolder {
                        return try ClaudeProjectFiles.createFolderAt(
                            parent: parent, name: trimmed)
                    }
                    return try ClaudeProjectFiles.createFileAt(
                        parent: parent, name: trimmed)
                }
            }.value
            pendingCreate = nil
            let route = Self.route(for: pending.section, createdURL: url, projectURL: projectURL)
            await reload(projectURL: projectURL)
            return route
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    func beginRename(url: URL) {
        renaming = RenameSession(url: url, name: url.lastPathComponent)
    }

    func cancelRename() {
        renaming = nil
    }

    @discardableResult
    func commitRename(projectURL: URL) async -> NavigatorRoute? {
        guard let session = renaming else { return nil }
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        do {
            let url = session.url
            let target = try await Task.detached(priority: .userInitiated) {
                try ClaudeProjectFiles.renameFile(at: url, to: trimmed)
            }.value
            renaming = nil
            routeRewrites = [
                .moved(
                    oldRelativePath: Self.relativePath(from: projectURL, to: url),
                    newRelativePath: Self.relativePath(from: projectURL, to: target))
            ]
            await reload(projectURL: projectURL)
            return Self.routeAfterRename(newURL: target, projectURL: projectURL)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    // Finder → tree drop. Copies each source URL into `targetFolder` with
    // a suffix walk on collision. Rejects targets outside the whitelisted
    // file-tree area (.claude/ subtree only).
    func handleFinderDrop(
        urls: [URL], targetFolder: URL, projectURL: URL
    ) async {
        guard !urls.isEmpty else { return }
        guard FileTreeDropResolver.isInsideWhitelistedTree(targetFolder, projectURL: projectURL)
        else {
            showBanner("Drop target outside managed area")
            return
        }
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try Self.performFinderCopy(sources: urls, destination: targetFolder)
            }.value
            if !outcome.rejected.isEmpty {
                showBanner(
                    "\(outcome.rejected.count) of "
                        + "\(outcome.accepted.count + outcome.rejected.count) "
                        + "files skipped")
            }
            if !outcome.accepted.isEmpty {
                await reload(projectURL: projectURL)
            }
        } catch {
            showBanner("Couldn't copy: \(error.localizedDescription)")
        }
    }

    // Tree-internal drag-move. Moves each source URL into `targetFolder`
    // via `ClaudeProjectFiles.moveItem`. Rejects self-into-subtree and
    // targets outside the whitelist.
    func handleInternalMove(
        sources: [URL], targetFolder: URL, projectURL: URL
    ) async {
        guard !sources.isEmpty else { return }
        guard FileTreeDropResolver.isInsideWhitelistedTree(targetFolder, projectURL: projectURL)
        else {
            showBanner("Drop target outside managed area")
            return
        }
        for source in sources where Self.isAncestor(source, of: targetFolder) {
            showBanner("Cannot move folder into its own subfolder")
            return
        }
        do {
            let moved = try await Task.detached(priority: .userInitiated) {
                () -> [(source: URL, target: URL)] in
                var results: [(source: URL, target: URL)] = []
                for source in sources {
                    let target = try ClaudeProjectFiles.moveItem(
                        at: source, to: targetFolder)
                    results.append((source, target))
                }
                return results
            }.value
            if !moved.isEmpty {
                routeRewrites = moved.map {
                    .moved(
                        oldRelativePath: Self.relativePath(from: projectURL, to: $0.source),
                        newRelativePath: Self.relativePath(from: projectURL, to: $0.target))
                }
                await reload(projectURL: projectURL)
            }
        } catch {
            showBanner("Couldn't move: \(error.localizedDescription)")
        }
    }

    func trash(url: URL, projectURL: URL) async {
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try ClaudeProjectFiles.trashFile(at: url)
            }.value
            routeRewrites = [
                .removed(oldRelativePath: Self.relativePath(from: projectURL, to: url))
            ]
            await reload(projectURL: projectURL)
        } catch {
            showBanner("Couldn't move to Trash: \(error.localizedDescription)")
        }
    }

    func showBanner(_ message: String) {
        bannerResetTask?.cancel()
        dropRejectMessage = message
        let duration = bannerDisplayDuration
        bannerResetTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dropRejectMessage = nil
        }
    }

    func clearBanner() {
        bannerResetTask?.cancel()
        dropRejectMessage = nil
    }

    private nonisolated static func isAncestor(_ ancestor: URL, of descendant: URL) -> Bool {
        let aPath = ancestor.standardizedFileURL.path
        let dPath = descendant.standardizedFileURL.path
        return aPath == dPath || dPath.hasPrefix(aPath + "/")
    }

    private nonisolated struct FinderCopyOutcome: Sendable {
        var accepted: [URL] = []
        var rejected: [URL] = []
    }

    private nonisolated static func performFinderCopy(
        sources: [URL], destination: URL
    ) throws -> FinderCopyOutcome {
        var outcome = FinderCopyOutcome()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination, withIntermediateDirectories: true)
        for source in sources {
            // Source already lives in the destination folder — treat as a
            // no-op. Otherwise findFreeName (which never returns a taken name)
            // walks to `name-1` and copyItem duplicates the file.
            if source.deletingLastPathComponent().standardizedFileURL.path
                == destination.standardizedFileURL.path
            {
                outcome.accepted.append(source)
                continue
            }
            let target = try ClaudeProjectFiles.findFreeName(
                in: destination, base: source.lastPathComponent)
            do {
                try fileManager.copyItem(at: source, to: target)
                outcome.accepted.append(target)
            } catch {
                outcome.rejected.append(source)
            }
        }
        return outcome
    }

    private static func route(
        for section: PendingCreate.Section, createdURL: URL, projectURL: URL
    ) -> NavigatorRoute? {
        switch section {
        case .treeNode(_, let isFolder):
            guard !isFolder else { return nil }
            let rel = relativePath(from: projectURL, to: createdURL)
            return .projectFile(relativePath: rel)
        }
    }

    private static func routeAfterRename(newURL: URL, projectURL: URL) -> NavigatorRoute? {
        let isDir = (try? newURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard !isDir else { return nil }
        let rel = relativePath(from: projectURL, to: newURL)
        return .projectFile(relativePath: rel)
    }

    static func relativePath(from projectURL: URL, to url: URL) -> String {
        let projectPath = projectURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(projectPath + "/") {
            return String(urlPath.dropFirst(projectPath.count + 1))
        }
        return url.lastPathComponent
    }
}

nonisolated struct PendingCreate: Identifiable, Equatable, Sendable {
    nonisolated enum Section: Hashable, Sendable {
        // Generic at-path create used by the unified file tree. `parent` is
        // the on-disk folder where the new entry lands. `isFolder` toggles
        // between file and folder creation.
        case treeNode(parent: URL, isFolder: Bool)

        var defaultName: String {
            switch self {
            case .treeNode(_, let isFolder): return isFolder ? "untitled" : "untitled.md"
            }
        }
    }

    let id: UUID
    let section: Section
    var name: String

    init(section: Section, name: String) {
        self.id = UUID()
        self.section = section
        self.name = name
    }
}

nonisolated struct RenameSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    var name: String

    init(url: URL, name: String) {
        self.id = UUID()
        self.url = url
        self.name = name
    }
}

// A project-relative path change the sidebar emitted via rename/move/trash.
// `ProjectWindow` matches these against the live selection (exact path or
// any descendant) to re-point or clear the detail pane. Paths are compared,
// not URLs, since the selection lives as `.projectFile(relativePath:)`.
nonisolated enum RouteRewrite: Equatable, Sendable {
    case moved(oldRelativePath: String, newRelativePath: String)
    case removed(oldRelativePath: String)
}
