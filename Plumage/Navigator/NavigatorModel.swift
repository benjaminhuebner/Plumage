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
    // Most recently created route — sidebar highlights it briefly so the
    // user spots the new row.
    private(set) var lastCreatedRoute: NavigatorRoute?

    private var bannerResetTask: Task<Void, Never>?
    private let bannerDisplayDuration: Duration

    init(bannerDisplayDuration: Duration = .seconds(3)) {
        self.bannerDisplayDuration = bannerDisplayDuration
    }

    func reload(projectURL: URL) async {
        let nodes = await Task.detached(priority: .userInitiated) {
            FileTreeBuilder.build(projectURL: projectURL)
        }.value
        self.rootNodes = nodes
        // `pendingCreate` is intentionally preserved across reloads — an
        // FSEvent triggered mid-inline-edit must not collapse the user's
        // open create row.
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
            lastCreatedRoute = route
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
            await reload(projectURL: projectURL)
            return Self.routeAfterRename(newURL: target, projectURL: projectURL)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    // Finder → tree drop. Copies each source URL into `targetFolder` with
    // a suffix walk on collision. Rejects targets outside the whitelisted
    // file-tree area (.claude/, .plumage/).
    func handleFinderDrop(
        urls: [URL], targetFolder: URL, projectURL: URL
    ) async {
        guard !urls.isEmpty else { return }
        guard Self.isInsideWhitelistedTree(targetFolder, projectURL: projectURL) else {
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
        guard Self.isInsideWhitelistedTree(targetFolder, projectURL: projectURL) else {
            showBanner("Drop target outside managed area")
            return
        }
        for source in sources where Self.isAncestor(source, of: targetFolder) {
            showBanner("Cannot move folder into its own subfolder")
            return
        }
        do {
            let moved = try await Task.detached(priority: .userInitiated) {
                () -> [URL] in
                var results: [URL] = []
                for source in sources {
                    let target = try ClaudeProjectFiles.moveItem(
                        at: source, to: targetFolder)
                    results.append(target)
                }
                return results
            }.value
            if !moved.isEmpty {
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

    private nonisolated static func isInsideWhitelistedTree(_ url: URL, projectURL: URL) -> Bool {
        let claude =
            projectURL.appendingPathComponent(FileTreeBuilder.claudeRoot, isDirectory: true)
            .standardizedFileURL.path
        let plumage =
            projectURL.appendingPathComponent(FileTreeBuilder.plumageRoot, isDirectory: true)
            .standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target == claude || target.hasPrefix(claude + "/")
            || target == plumage || target.hasPrefix(plumage + "/")
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
            let target = try ClaudeProjectFiles.findFreeName(
                in: destination, base: source.lastPathComponent)
            if target.standardizedFileURL.path == source.standardizedFileURL.path {
                outcome.accepted.append(target)
                continue
            }
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
