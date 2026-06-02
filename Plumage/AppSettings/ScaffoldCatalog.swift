import Foundation

nonisolated enum ScaffoldCatalog {
    typealias Entry = TemplatesSettingsModel.CatalogEntry
    typealias Category = TemplatesSettingsModel.Category

    static func build(overrides: ScaffoldOverrides) -> [Entry] {
        var result = bundledEntries(root: overrides.bundledRoot)
        let bundledPaths = Set(result.map(\.relativePath))

        // Agents have no bundled baseline: the catalog is the override store.
        for name in overrides.overrideFileNames(inRelativeDir: "agents") {
            result.append(
                Entry(
                    relativePath: "agents/\(name)", category: .agents, label: name,
                    userAuthored: true))
        }

        // Docs and plumage scripts: the bundled files are already listed; add any
        // override-only files the user authored (skipping overrides of bundled files,
        // which are the same entries with an override on disk).
        let unionDirs: [(dir: String, category: Category)] = [
            ("docs", .docs), ("plumage", .plumageScripts),
        ]
        for (dir, category) in unionDirs {
            for name in overrides.overrideFileNames(inRelativeDir: dir) {
                let rel = "\(dir)/\(name)"
                guard !bundledPaths.contains(rel) else { continue }
                result.append(
                    Entry(
                        relativePath: rel, category: category, label: name, userAuthored: true))
            }
        }

        // Hooks: add override-only `.sh` files (overrides of bundled hooks are
        // already listed as bundled entries).
        for name in overrides.overrideFileNames(inRelativeDir: "hooks") where name.hasSuffix(".sh") {
            let rel = "hooks/\(name)"
            guard !bundledPaths.contains(rel) else { continue }
            result.append(
                Entry(relativePath: rel, category: .hooks, label: name, userAuthored: true))
        }

        // Skills are directories: enumerate each override skill tree and add its
        // override-only files (overrides of bundled skill files are already listed).
        for skill in overrides.overrideSkillDirNames() {
            for sub in overrides.overrideFileNamesRecursive(inRelativeDir: "skills/\(skill)") {
                let rel = "skills/\(skill)/\(sub)"
                guard !bundledPaths.contains(rel) else { continue }
                result.append(
                    Entry(
                        relativePath: rel, category: .skills, label: "\(skill)/\(sub)",
                        userAuthored: true))
            }
        }
        return result
    }

    private static func bundledEntries(root: URL) -> [Entry] {
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return [] }

        let rootPath = root.standardizedFileURL.path + "/"
        var result: [Entry] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let rel = url.standardizedFileURL.path.replacingOccurrences(of: rootPath, with: "")
            guard let category = category(for: rel) else { continue }
            result.append(
                Entry(
                    relativePath: rel, category: category,
                    label: label(for: rel, category: category), userAuthored: false))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    private static func category(for rel: String) -> Category? {
        // gitignore is a sub-prefix of templates/, so check it first.
        if rel.hasPrefix(Category.gitignore.folderPrefix) { return .gitignore }
        for category in Category.allCases where category != .gitignore && category != .agents {
            if rel.hasPrefix(category.folderPrefix) { return category }
        }
        return nil
    }

    private static func label(for rel: String, category: Category) -> String {
        String(rel.dropFirst(category.folderPrefix.count))
    }
}
