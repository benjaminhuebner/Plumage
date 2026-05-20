import Foundation

@MainActor
@Observable
final class NavigatorModel {
    private(set) var docs: [URL] = []
    private(set) var claudeMarkdown: [URL] = []
    private(set) var hooks: [URL] = []
    private(set) var skills: [SkillNode] = []
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
    // Folder name (issue ID) of the most recently created item — used by the
    // sidebar to highlight the new row briefly so the user spots it.
    private(set) var lastCreatedRoute: NavigatorRoute?

    private var bannerResetTask: Task<Void, Never>?
    private let bannerDisplayDuration: Duration

    init(bannerDisplayDuration: Duration = .seconds(3)) {
        self.bannerDisplayDuration = bannerDisplayDuration
    }

    func reload(projectURL: URL) async {
        let snapshot = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            var snap = Snapshot()
            do {
                snap.docs = try ClaudeProjectFiles.enumerateDocs(projectURL: projectURL)
                snap.claudeMarkdown = try ClaudeProjectFiles.enumerateClaudeMarkdown(
                    projectURL: projectURL)
                snap.hooks = try ClaudeProjectFiles.enumerateHooks(projectURL: projectURL)
                snap.skills = try ClaudeProjectFiles.enumerateSkills(projectURL: projectURL)
            } catch {
                snap.error = error.localizedDescription
            }
            return snap
        }.value
        self.docs = snapshot.docs
        self.claudeMarkdown = snapshot.claudeMarkdown
        self.hooks = snapshot.hooks
        self.skills = snapshot.skills
        self.loadError = snapshot.error
        // `pendingCreate` is intentionally preserved across reloads — an
        // FSEvent triggered mid-inline-edit must not collapse the user's
        // open create row.
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
                case .docs:
                    return try ClaudeProjectFiles.createDoc(
                        name: trimmed, projectURL: projectURL)
                case .claudeMarkdown:
                    return try ClaudeProjectFiles.createClaudeMarkdown(
                        name: trimmed, projectURL: projectURL)
                case .hookFile:
                    return try ClaudeProjectFiles.createHookFile(
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
        case .docs:
            let relative = relativePath(from: projectURL, to: createdURL)
            return .doc(relativePath: relative)
        case .claudeMarkdown:
            return .claudeMarkdown(name: createdURL.lastPathComponent)
        case .hookFile:
            return .hook(name: createdURL.lastPathComponent)
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
        }
    }

    // After a successful rename we want the selection to follow the new
    // path. For docs we need the `.claude/docs/<name>`-relative form, for
    // claudeMarkdown we need just the name, etc. We piggy-back on the same
    // section/route mapping the create flow uses.
    private static func routeAfterRename(
        originalURL: URL, newURL: URL, projectURL: URL
    ) -> NavigatorRoute? {
        let path = newURL.standardizedFileURL.path
        let projectPath = projectURL.standardizedFileURL.path
        guard path.hasPrefix(projectPath + "/") else { return nil }
        let relative = String(path.dropFirst(projectPath.count + 1))
        if relative.hasPrefix(".claude/docs/") {
            return .doc(relativePath: relative)
        }
        if newURL.deletingLastPathComponent().lastPathComponent == ".claude" {
            return .claudeMarkdown(name: newURL.lastPathComponent)
        }
        if relative.hasPrefix(".claude/hooks/") {
            return .hook(name: newURL.lastPathComponent)
        }
        if relative.hasPrefix(".claude/skills/") {
            // Treat the first path component below `skills/` as the
            // skill folder; the rest is the relative path.
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
}

nonisolated struct PendingCreate: Identifiable, Equatable, Sendable {
    nonisolated enum Section: Hashable, Sendable {
        case docs
        case claudeMarkdown
        case hookFile
        case hookFolder
        case skill
        case skillFolder(skillName: String, relativePath: String)
        case skillFile(skillName: String, relativePath: String)

        var defaultName: String {
            switch self {
            case .docs, .claudeMarkdown: return "untitled.md"
            case .hookFile: return "untitled.sh"
            case .hookFolder: return "untitled"
            case .skill: return "untitled-skill"
            case .skillFolder: return "untitled"
            case .skillFile: return "untitled.md"
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
    var docs: [URL] = []
    var claudeMarkdown: [URL] = []
    var hooks: [URL] = []
    var skills: [SkillNode] = []
    var error: String?
}
