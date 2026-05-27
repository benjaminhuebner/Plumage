import Foundation

@MainActor
@Observable
final class NavigatorModel {
    // Per-type managed-file lists. Indexed lookups go through `items(for:)`.
    // `claudeMarkdown` lives outside this dict because `.claude/` root is not
    // a `ManagedFileType`; skills have their own tree.
    private(set) var enumeratedItems: [ManagedFileType: [URL]] = [:]
    private(set) var claudeMarkdown: [URL] = []
    private(set) var skills: [SkillNode] = []
    private(set) var claudeLocalMDExists: Bool = false
    private(set) var mcpJSONExists: Bool = false
    private(set) var loadError: String?

    // Unified file tree powering the upcoming "Files" sidebar section.
    // Built off-Main from `FileTreeBuilder.build(...)` on every reload.
    // Old per-type lists above stay populated in parallel until the sidebar
    // rewrite consumes `rootNodes` directly.
    private(set) var rootNodes: [FileNode] = []

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
    // Folder name (issue ID) of the most recently created item — used by the
    // sidebar to highlight the new row briefly so the user spots it.
    private(set) var lastCreatedRoute: NavigatorRoute?

    private var bannerResetTask: Task<Void, Never>?
    private let bannerDisplayDuration: Duration

    init(bannerDisplayDuration: Duration = .seconds(3)) {
        self.bannerDisplayDuration = bannerDisplayDuration
    }

    func items(for type: ManagedFileType) -> [URL] {
        enumeratedItems[type] ?? []
    }

    // Convenience accessors so call-sites keep reading `.docs` / `.hooks`
    // without knowing the dict is the storage form.
    var docs: [URL] { items(for: .docs) }
    var hooks: [URL] { items(for: .hooks) }
    var agents: [URL] { items(for: .agents) }
    var rules: [URL] { items(for: .rules) }
    var outputStyles: [URL] { items(for: .outputStyles) }

    func reload(projectURL: URL) async {
        let snapshot = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            var snap = Snapshot()
            // Existence checks are cheap and never throw — run them up-front so
            // a failure further down (e.g. enumerate on a missing-permission
            // .claude/docs) doesn't hide the CLAUDE.local.md / .mcp.json rows.
            let fm = FileManager.default
            snap.claudeLocalMDExists = fm.fileExists(
                atPath: ClaudeProjectFiles.claudeLocalMDURL(projectURL: projectURL).path)
            snap.mcpJSONExists = fm.fileExists(
                atPath: ClaudeProjectFiles.mcpJSONURL(projectURL: projectURL).path)
            do {
                for type in ManagedFileType.allCases {
                    snap.items[type] = try ClaudeProjectFiles.enumerate(
                        type, projectURL: projectURL)
                }
                snap.claudeMarkdown = try ClaudeProjectFiles.enumerateClaudeMarkdown(
                    projectURL: projectURL)
                snap.skills = try ClaudeProjectFiles.enumerateSkills(projectURL: projectURL)
            } catch {
                snap.error = error.localizedDescription
            }
            return snap
        }.value
        self.enumeratedItems = snapshot.items
        self.claudeMarkdown = snapshot.claudeMarkdown
        self.skills = snapshot.skills
        self.claudeLocalMDExists = snapshot.claudeLocalMDExists
        self.mcpJSONExists = snapshot.mcpJSONExists
        self.loadError = snapshot.error
        let nodes = await Task.detached(priority: .userInitiated) {
            FileTreeBuilder.build(projectURL: projectURL)
        }.value
        self.rootNodes = nodes
        // `pendingCreate` is intentionally preserved across reloads — an
        // FSEvent triggered mid-inline-edit must not collapse the user's
        // open create row.
    }

    // Finder → tree drop. Copies each source URL into `targetFolder` with
    // a suffix walk on collision. Rejects targets outside the whitelisted
    // file-tree area (.claude/, .plumage/). One banner per drop with the
    // accept/reject split rolled up.
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
    // via `FileManager.moveItem` with a suffix walk on collision. Rejects
    // self-into-subtree moves and targets outside the whitelist.
    func handleInternalMove(
        sources: [URL], targetFolder: URL, projectURL: URL
    ) async {
        guard !sources.isEmpty else { return }
        guard Self.isInsideWhitelistedTree(targetFolder, projectURL: projectURL) else {
            showBanner("Drop target outside managed area")
            return
        }
        for source in sources {
            if Self.isAncestor(source, of: targetFolder) {
                showBanner("Cannot move folder into its own subfolder")
                return
            }
        }
        do {
            let moved = try await Task.detached(priority: .userInitiated) {
                () -> [URL] in
                var results: [URL] = []
                for source in sources {
                    let target = try ClaudeProjectFiles.findFreeName(
                        in: targetFolder, base: source.lastPathComponent)
                    if target.standardizedFileURL.path == source.standardizedFileURL.path {
                        results.append(target)
                        continue
                    }
                    try FileManager.default.moveItem(at: source, to: target)
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

    func beginPendingCreate(_ section: PendingCreate.Section) {
        pendingCreate = PendingCreate(section: section, name: section.defaultName)
    }

    func cancelPendingCreate() {
        pendingCreate = nil
    }

    func isPendingCreate(at section: PendingCreate.Section) -> Bool {
        pendingCreate?.section == section
    }

    // Resolves the active pendingCreate against disk: creates the file or
    // folder via `ClaudeProjectFiles` and returns the resulting route. Empty
    // input is a no-op (leaves the textfield focused). Disk errors land in
    // `dropRejectMessage`; the inline row stays so the user can retry or
    // escape.
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
                case .managedFile(let type):
                    return try ClaudeProjectFiles.create(
                        type, name: trimmed, projectURL: projectURL)
                case .claudeMarkdown:
                    return try ClaudeProjectFiles.createClaudeMarkdown(
                        name: trimmed, projectURL: projectURL)
                case .hookFolder:
                    return try ClaudeProjectFiles.createHookFolder(
                        name: trimmed, projectURL: projectURL)
                case .skill:
                    return try ClaudeProjectFiles.createSkill(
                        name: trimmed, projectURL: projectURL)
                case .skillFolder(let skill, let path):
                    return try ClaudeProjectFiles.createSkillFolder(
                        name: trimmed, underSkill: skill, relativePath: path,
                        projectURL: projectURL)
                case .skillFile(let skill, let path):
                    return try ClaudeProjectFiles.createSkillFile(
                        name: trimmed, underSkill: skill, relativePath: path,
                        projectURL: projectURL)
                case .treeNode(let parent, let isFolder):
                    guard isFolder else {
                        return try ClaudeProjectFiles.createFileAt(
                            parent: parent, name: trimmed)
                    }
                    return try ClaudeProjectFiles.createFolderAt(
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

    // Triggers the ~3 s reject banner. Cancels any in-flight auto-dismiss
    // task before scheduling the new one so back-to-back errors don't fight
    // each other.
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
                try ClaudeProjectFiles.renameFile(
                    at: url, to: trimmed, projectURL: projectURL)
            }.value
            renaming = nil
            await reload(projectURL: projectURL)
            return Self.routeAfterRename(originalURL: session.url, newURL: target, projectURL: projectURL)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    // Finder-drop entry point. Copies the source URLs into the section's
    // destination directory off-Main, then reloads the navigator snapshot.
    // Mixed accept/reject is rolled into one banner; FS errors land in
    // `dropRejectMessage` and the navigator state stays consistent.
    func handleFinderDrop(
        urls: [URL], section: SidebarDropTarget.Section, projectURL: URL
    ) async {
        guard !urls.isEmpty else { return }
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try SidebarDropTarget.performDrop(
                    sources: urls, section: section, projectURL: projectURL)
            }.value
            if let banner = SidebarDropTarget.bannerMessage(
                outcome: outcome, section: section)
            {
                showBanner(banner)
            }
            if !outcome.accepted.isEmpty {
                await reload(projectURL: projectURL)
            }
        } catch {
            showBanner("Couldn't copy: \(error.localizedDescription)")
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

    private static func route(
        for section: PendingCreate.Section, createdURL: URL, projectURL: URL
    ) -> NavigatorRoute? {
        switch section {
        case .managedFile(let type):
            let rel = relativeSubpath(
                from: projectURL, to: createdURL, base: type.relativePath)
            return .managedFile(type: type, relativePath: rel)
        case .claudeMarkdown:
            return .claudeMarkdown(name: createdURL.lastPathComponent)
        case .hookFolder:
            // Folders aren't a selectable route — sidebar keeps the previous
            // selection so the user doesn't get bounced.
            return nil
        case .skill:
            return .skillFile(skill: createdURL.lastPathComponent, relativePath: "SKILL.md")
        case .skillFolder:
            // Skill sub-folder — also non-selectable; user creates files
            // inside it as the next step.
            return nil
        case .skillFile(let skill, let path):
            let leaf = createdURL.lastPathComponent
            let rel = path.isEmpty ? leaf : "\(path)/\(leaf)"
            return .skillFile(skill: skill, relativePath: rel)
        case .treeNode(_, let isFolder):
            guard !isFolder else { return nil }
            let rel = relativePath(from: projectURL, to: createdURL)
            return .projectFile(relativePath: rel)
        }
    }

    // After a successful rename we want the selection to follow the new
    // path. For managed-file types we strip the type's base path; for free
    // `.claude/`-root markdown we keep just the file name; for skill files
    // we split off the first path component below `skills/`.
    private static func routeAfterRename(
        originalURL: URL, newURL: URL, projectURL: URL
    ) -> NavigatorRoute? {
        let path = newURL.standardizedFileURL.path
        let projectPath = projectURL.standardizedFileURL.path
        guard path.hasPrefix(projectPath + "/") else { return nil }
        let relative = String(path.dropFirst(projectPath.count + 1))
        for type in ManagedFileType.allCases {
            let base = type.relativePath + "/"
            if relative.hasPrefix(base) {
                let rel = String(relative.dropFirst(base.count))
                return .managedFile(type: type, relativePath: rel)
            }
        }
        if newURL.deletingLastPathComponent().lastPathComponent == ".claude" {
            return .claudeMarkdown(name: newURL.lastPathComponent)
        }
        if relative.hasPrefix(".claude/skills/") {
            let trimmed = String(relative.dropFirst(".claude/skills/".count))
            let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return .skillFile(skill: parts[0], relativePath: parts[1])
            }
        }
        return nil
    }

    static func relativePath(from projectURL: URL, to url: URL) -> String {
        let projectPath = projectURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(projectPath + "/") {
            return String(urlPath.dropFirst(projectPath.count + 1))
        }
        return url.lastPathComponent
    }

    fileprivate static func relativeSubpath(
        from projectURL: URL, to url: URL, base: String
    ) -> String {
        let full = relativePath(from: projectURL, to: url)
        let prefix = base + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }
}

nonisolated struct PendingCreate: Identifiable, Equatable, Sendable {
    nonisolated enum Section: Hashable, Sendable {
        case managedFile(type: ManagedFileType)
        case claudeMarkdown
        case hookFolder
        case skill
        case skillFolder(skillName: String, relativePath: String)
        case skillFile(skillName: String, relativePath: String)
        // Generic at-path create used by the unified file tree. `parent` is
        // the on-disk folder where the new entry lands. `isFolder` toggles
        // between file and folder creation (different commit paths +
        // default names).
        case treeNode(parent: URL, isFolder: Bool)

        var defaultName: String {
            switch self {
            case .managedFile(let type): return type.defaultName
            case .claudeMarkdown: return "untitled.md"
            case .hookFolder: return "untitled"
            case .skill: return "untitled-skill"
            case .skillFolder: return "untitled"
            case .skillFile: return "untitled.md"
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

private struct Snapshot: Sendable {
    var items: [ManagedFileType: [URL]] = [:]
    var claudeMarkdown: [URL] = []
    var skills: [SkillNode] = []
    var claudeLocalMDExists: Bool = false
    var mcpJSONExists: Bool = false
    var error: String?
}
