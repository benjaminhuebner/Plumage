import Foundation
import SwiftUI

@MainActor
@Observable
final class NavigatorModel {
    // Unified file tree state. Built off-Main from `FileTreeBuilder.build(...)`
    // on every reload.
    private(set) var rootNodes: [FileNode] = []
    private(set) var loadError: String?

    // Relative paths of every effectively-empty foundation context file in the
    // current tree, recomputed on each reload. A *stored* observed property (not
    // computed) so every sidebar row that reads it — file row, collapsed folder,
    // pinned shortcut — is individually invalidated the instant it changes,
    // rather than waiting for the NSTableView-backed List to re-diff stable rows
    // on the next click. That direct per-row observation is what makes the
    // warning flip live without a stray interaction.
    private(set) var emptyContextFilePaths: Set<String> = []

    // Relative paths of every folder that *hides* an empty context file in its
    // subtree, so a collapsed folder row can warn with a single O(1) lookup
    // instead of scanning `emptyContextFilePaths` with a prefix match per render.
    // Derived from `emptyContextFilePaths`, so it only changes when that does.
    private(set) var foldersHidingEmptyContextFile: Set<String> = []

    // Inline rename of an existing row. Set when the user hits Enter or
    // picks "Rename" from the context menu; cleared on commit/cancel.
    var renaming: RenameSession?

    // Expanded folder paths of the sidebar file tree, persisted per project
    // so expansion survives app restart.
    var fileTreeExpansion: Set<String> = [] {
        didSet { persistExpansion() }
    }
    private var expansionProject: URL?
    private var isLoadingExpansion = false
    private var expansionPersist: Task<Void, Never>?

    // Scroll/expand the sidebar tree to a programmatically created node —
    // selection alone can't surface a row hidden under a collapsed folder.
    private(set) var sidebarReveal: FileTreeRevealRequest?

    // Set by the Delete key / context-menu "Move to Trash"; the sidebar
    // presents a confirmation dialog for it. Trash is recoverable, but the
    // file disappears instantly from the project — no unconfirmed destruction.
    private(set) var pendingTrash: [URL]?

    func requestTrash(url: URL) {
        requestTrash(urls: [url])
    }

    func requestTrash(urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingTrash = urls
    }

    func cancelPendingTrash() {
        pendingTrash = nil
    }

    func confirmPendingTrash(projectURL: URL) async {
        guard let urls = pendingTrash else { return }
        pendingTrash = nil
        await trash(urls: urls, projectURL: projectURL)
    }

    var pendingTrashTitle: String {
        guard let urls = pendingTrash, !urls.isEmpty else { return "" }
        if urls.count == 1 {
            return "Move \"\(urls[0].lastPathComponent)\" to Trash?"
        }
        return "Move \(urls.count) items to Trash?"
    }

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

    // Cancel the auto-reset banner task on teardown — consistent with the
    // other @Observable models that own Tasks. (`[weak self]` already prevents
    // retention; this just stops the timer from outliving the model.)
    isolated deinit {
        bannerResetTask?.cancel()
    }

    func reload(projectURL: URL) async {
        if expansionProject != projectURL {
            expansionProject = projectURL
            isLoadingExpansion = true
            fileTreeExpansion = await Task.detached(priority: .userInitiated) {
                SidebarExpansionStore.load(projectURL: projectURL)
            }.value
            isLoadingExpansion = false
        }
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
        // Guard the assignment: `@Observable` fires on every set regardless of
        // equality, so reassigning an identical set on an unrelated FSEvent
        // reload would re-render every row that reads it. Only publish on a
        // real change — the derived folder set is recomputed in lockstep.
        let newEmptyPaths = Self.collectEmptyContextPaths(result.nodes)
        if newEmptyPaths != emptyContextFilePaths {
            self.emptyContextFilePaths = newEmptyPaths
            self.foldersHidingEmptyContextFile = Self.collectFoldersHidingEmptyContextPaths(
                newEmptyPaths)
        }
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
        // `renaming` is intentionally preserved across reloads — an FSEvent
        // triggered mid-inline-edit must not kill the user's edit session.
    }

    // Chained off the prior write (RecentProjects discipline): independent
    // fire-and-forget tasks can land on disk out of order.
    private func persistExpansion() {
        guard let projectURL = expansionProject, !isLoadingExpansion else { return }
        let paths = fileTreeExpansion
        let prior = expansionPersist
        expansionPersist = Task.detached(priority: .utility) {
            await prior?.value
            SidebarExpansionStore.save(paths, projectURL: projectURL)
        }
    }

    // Flat set of every empty-context file's relative path in a built tree.
    nonisolated static func collectEmptyContextPaths(_ nodes: [FileNode]) -> Set<String> {
        var result: Set<String> = []
        func walk(_ node: FileNode) {
            if node.isEmptyContextFile { result.insert(node.relativePath) }
            node.children?.forEach(walk)
        }
        nodes.forEach(walk)
        return result
    }

    // Precomputed once per reload so a collapsed-folder row can warn with an
    // O(1) Set lookup instead of a per-render `hasPrefix` scan over every path.
    nonisolated static func collectFoldersHidingEmptyContextPaths(
        _ emptyPaths: Set<String>
    ) -> Set<String> {
        var result: Set<String> = []
        for path in emptyPaths {
            var components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            components.removeLast()
            var prefix = ""
            for component in components {
                prefix = prefix.isEmpty ? component : prefix + "/" + component
                result.insert(prefix)
            }
        }
        return result
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

    // Finder's new-file idiom: create with a free default name immediately,
    // reveal the row, and start inline rename so the user types the real name.
    @discardableResult
    func createAndReveal(parent: URL, isFolder: Bool, projectURL: URL) async -> NavigatorRoute? {
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                isFolder
                    ? try ClaudeProjectFiles.createFolderAt(parent: parent, name: "untitled")
                    : try ClaudeProjectFiles.createFileAt(parent: parent, name: "untitled.md")
            }.value
            await reload(projectURL: projectURL)
            let relativePath = Self.relativePath(from: projectURL, to: url)
            sidebarReveal = FileTreeRevealRequest(path: relativePath)
            beginRename(url: url)
            return .projectFile(relativePath: relativePath)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    func beginRename(url: URL) {
        renaming = RenameSession(url: url, name: url.lastPathComponent)
    }

    // Model-owned binding keeps Binding(get:set:) out of view bodies.
    var renameNameBinding: Binding<String> {
        Binding(
            get: { self.renaming?.name ?? "" },
            set: { if self.renaming != nil { self.renaming?.name = $0 } })
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
        await trash(urls: [url], projectURL: projectURL)
    }

    // Batch trash with partial-failure semantics: completed trashes stand,
    // the banner names what failed, the reload reflects on-disk reality.
    func trash(urls: [URL], projectURL: URL) async {
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (trashed: [URL], failed: [String]) in
            var trashed: [URL] = []
            var failed: [String] = []
            for url in urls {
                do {
                    _ = try ClaudeProjectFiles.trashFile(at: url)
                    trashed.append(url)
                } catch {
                    failed.append(url.lastPathComponent)
                }
            }
            return (trashed, failed)
        }.value
        if !outcome.trashed.isEmpty {
            routeRewrites = outcome.trashed.map {
                .removed(oldRelativePath: Self.relativePath(from: projectURL, to: $0))
            }
            await reload(projectURL: projectURL)
        }
        if !outcome.failed.isEmpty {
            showBanner("Couldn't move to Trash: \(outcome.failed.joined(separator: ", "))")
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
