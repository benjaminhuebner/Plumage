import Foundation

// Installs Plumage's bundled `plumage` claude theme into ~/.claude/ so the
// embedded terminal renders without opaque block backgrounds, regardless of
// macOS appearance. The bundled JSON is the single source of truth; we
// overwrite on each Plumage boot so a Plumage update can ship a refreshed
// theme. Settings.json is updated more carefully — only flip `theme` to
// `plumage` if the user hasn't explicitly chosen a different non-plumage
// theme since the last install (i.e., if the field is missing OR already
// set to `plumage`).
// Pure file-I/O type with no UI state. Nonisolated so it can run from any
// context (NSApplicationDelegate callback, tests, etc.) without forcing a
// hop to MainActor — the default-actor-isolation project setting would
// otherwise pin it to MainActor.
nonisolated enum ClaudeThemeInstaller {
    enum InstallError: Error {
        case bundleResourceMissing
        case homeDirectoryUnavailable
    }

    static let themeName = "plumage"
    // claude's settings.json stores custom themes with a `custom:` prefix —
    // a bare `"theme": "plumage"` is treated as an unknown built-in name and
    // silently falls back to "Dark mode". The custom-theme file in
    // ~/.claude/themes/<name>.json keeps its bare name; only the settings.json
    // value gets the prefix. Verified against claude 2.1.150 by selecting
    // "plumage (custom)" through `/theme` and reading back the stored value.
    static let settingsThemeValue = "custom:\(themeName)"
    static let bundledResource = "plumage-theme"
    static let bundledExtension = "json"

    static func installIfNeeded(bundle: Bundle = .main, fileManager: FileManager = .default) {
        do {
            guard
                let sourceURL = bundle.url(
                    forResource: bundledResource, withExtension: bundledExtension)
            else { throw InstallError.bundleResourceMissing }
            try writeThemeFile(sourceURL: sourceURL, fileManager: fileManager)
            try ensureSettingsTheme(fileManager: fileManager)
        } catch {
            // Theme install is best-effort. A failure here must not block
            // Plumage's startup — the embedded terminal still works with
            // whatever theme claude picks up.
        }
    }

    static func writeThemeFile(
        sourceURL: URL,
        fileManager: FileManager = .default,
        destination: URL? = nil
    ) throws {
        let data = try Data(contentsOf: sourceURL)
        let target = try destination ?? defaultThemeFileURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    static func ensureSettingsTheme(
        fileManager: FileManager = .default,
        settingsURL: URL? = nil
    ) throws {
        let url = try settingsURL ?? defaultSettingsFileURL(fileManager: fileManager)
        var json: [String: Any]
        if fileManager.fileExists(atPath: url.path) {
            // File exists but unreadable or unparseable: bail rather than
            // clobber. settings.json is shared state owned by claude — an
            // overwrite would destroy api_key_helper / permissions / model
            // entries that other tooling depends on. Theme install is best-
            // effort; skipping is safer than data loss.
            guard let data = try? Data(contentsOf: url),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            json = parsed
        } else {
            json = [:]
        }
        // Only set theme if absent or already pointing at our theme. Accept
        // both `custom:plumage` (the value claude expects) and the legacy bare
        // `plumage` from earlier Plumage builds so we migrate that forward
        // without surprising users. Any other value is a manual user choice
        // and stays put.
        let current = json["theme"] as? String
        let isOurValue = current == settingsThemeValue || current == themeName
        if current == nil || isOurValue {
            json["theme"] = settingsThemeValue
            let updated = try JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: url, options: .atomic)
        }
    }

    static func defaultThemeFileURL(fileManager: FileManager) throws -> URL {
        try claudeHomeDirectory(fileManager: fileManager)
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent("\(themeName).json")
    }

    static func defaultSettingsFileURL(fileManager: FileManager) throws -> URL {
        try claudeHomeDirectory(fileManager: fileManager)
            .appendingPathComponent("settings.json")
    }

    private static func claudeHomeDirectory(fileManager: FileManager) throws -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        guard !home.path.isEmpty else { throw InstallError.homeDirectoryUnavailable }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }
}
