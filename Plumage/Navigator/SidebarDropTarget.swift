import Foundation

// Pure FileManager copy helper used by sidebar Finder-drop closures. Returns
// a `DropOutcome` so the view layer can render one banner per drop with the
// accept/reject split rolled up (analog to "3 of 5 files skipped").
nonisolated enum SidebarDropTarget {
    enum Section: Sendable, Hashable {
        case docs
        case claudeMarkdown
        case hooks
        case skillsTopLevel
        case skillSub(skillName: String, relativePath: String)
        case hookSub(relativePath: String)

        // Extensions accepted as plain files; folder drops are accepted
        // separately. An empty set means "no plain files allowed".
        var fileExtensions: Set<String> {
            switch self {
            case .docs, .claudeMarkdown:
                return ["md"]
            case .hooks, .hookSub:
                return ["sh", "py"]
            case .skillsTopLevel, .skillSub:
                return ["md", "sh", "py"]
            }
        }

        var rejectionMessage: String {
            switch self {
            case .docs: return "Only .md files allowed in Docs"
            case .claudeMarkdown: return "Only .md files allowed at .claude/ root"
            case .hooks, .hookSub: return "Only .sh/.py files or folders allowed in Hooks"
            case .skillsTopLevel, .skillSub: return "Only .md/.sh/.py files or folders allowed in Skills"
            }
        }

        // Resolves to an absolute target directory under projectURL.
        func destinationDirectory(projectURL: URL) -> URL {
            switch self {
            case .docs:
                return projectURL.appendingPathComponent(ClaudeProjectFiles.docsRelativePath, isDirectory: true)
            case .claudeMarkdown:
                return projectURL.appendingPathComponent(ClaudeProjectFiles.settingsRootRelativePath, isDirectory: true)
            case .hooks:
                return projectURL.appendingPathComponent(ClaudeProjectFiles.hooksRelativePath, isDirectory: true)
            case .hookSub(let rel):
                return appended(
                    base: projectURL.appendingPathComponent(ClaudeProjectFiles.hooksRelativePath, isDirectory: true),
                    relative: rel)
            case .skillsTopLevel:
                return projectURL.appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
            case .skillSub(let skill, let rel):
                return appended(
                    base:
                        projectURL
                        .appendingPathComponent(ClaudeProjectFiles.skillsRelativePath, isDirectory: true)
                        .appendingPathComponent(skill, isDirectory: true),
                    relative: rel)
            }
        }

        var allowsFolderDrop: Bool {
            switch self {
            case .docs, .claudeMarkdown: return false
            case .hooks, .hookSub, .skillsTopLevel, .skillSub: return true
            }
        }

        private func appended(base: URL, relative: String) -> URL {
            let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if trimmed.isEmpty { return base }
            var url = base
            for component in trimmed.split(separator: "/") {
                url = url.appendingPathComponent(String(component), isDirectory: true)
            }
            return url
        }
    }

    struct DropOutcome: Equatable, Sendable {
        var accepted: [URL] = []
        var rejected: [URL] = []
    }

    // Resolves a y-coordinate (in the sidebar's named coordinate space) to
    // the section whose header sits above it. Each section header reports
    // its minY into `anchors`; this walks them sorted ascending and returns
    // the last section whose minY <= y. Returns nil when y is above every
    // tracked header (e.g. cursor sits in the Issues area which doesn't
    // accept Finder drops).
    static func resolveSection(
        at y: CGFloat, anchors: [Section: CGFloat]
    ) -> Section? {
        let sorted = anchors.sorted { $0.value < $1.value }
        var winner: Section?
        for (section, minY) in sorted where minY <= y {
            winner = section
        }
        return winner
    }

    // Performs the copy + suffix walk for each source URL. Each source is
    // classified as file-or-folder, validated against the section's allowed
    // extensions / folder rule, and either copied or recorded as rejected.
    // Returns the outcome so the caller can decide whether to banner.
    static func performDrop(
        sources: [URL], section: Section, projectURL: URL
    ) throws -> DropOutcome {
        var outcome = DropOutcome()
        let fileManager = FileManager.default
        let destination = section.destinationDirectory(projectURL: projectURL)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for source in sources {
            let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                guard section.allowsFolderDrop else {
                    outcome.rejected.append(source)
                    continue
                }
                let target = try ClaudeProjectFiles.findFreeName(
                    in: destination, base: source.lastPathComponent)
                // Source == destination after suffix walk: skip (no-op, no error).
                if target.standardizedFileURL.path == source.standardizedFileURL.path {
                    outcome.accepted.append(target)
                    continue
                }
                try fileManager.copyItem(at: source, to: target)
                outcome.accepted.append(target)
            } else {
                let ext = source.pathExtension.lowercased()
                if section.fileExtensions.contains(ext) {
                    // Section-specific: top-level skill-drop with a file
                    // wraps the file in an implicit skill folder named after
                    // the file's stem (spec).
                    let target: URL
                    if case .skillsTopLevel = section {
                        target = try wrapFileAsSkill(source: source, destination: destination)
                    } else {
                        target = try ClaudeProjectFiles.findFreeName(
                            in: destination, base: source.lastPathComponent)
                        if target.standardizedFileURL.path == source.standardizedFileURL.path {
                            outcome.accepted.append(target)
                            continue
                        }
                        try fileManager.copyItem(at: source, to: target)
                    }
                    outcome.accepted.append(target)
                } else {
                    outcome.rejected.append(source)
                }
            }
        }
        return outcome
    }

    // Builds a banner string for a mixed-outcome drop. Returns nil if all
    // sources were accepted (no message to show).
    static func bannerMessage(outcome: DropOutcome, section: Section) -> String? {
        if outcome.rejected.isEmpty { return nil }
        if outcome.accepted.isEmpty {
            return section.rejectionMessage
        }
        let rejected = outcome.rejected.count
        let total = outcome.accepted.count + outcome.rejected.count
        return "\(rejected) of \(total) files skipped — \(section.rejectionMessage)"
    }

    private static func wrapFileAsSkill(source: URL, destination: URL) throws -> URL {
        let stem = (source.lastPathComponent as NSString).deletingPathExtension
        let skillFolder = try ClaudeProjectFiles.findFreeName(in: destination, base: stem)
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: false)
        let copyDestination = skillFolder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copyDestination)
        return skillFolder
    }
}
