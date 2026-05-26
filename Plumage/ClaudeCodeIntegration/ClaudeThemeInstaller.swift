import Foundation

// Installs Plumage's bundled `plumage` claude theme into ~/.claude/themes/ so
// the embedded terminal renders without opaque block backgrounds, regardless
// of macOS appearance. The bundled JSON is the single source of truth; we
// overwrite on each Plumage boot so a Plumage update can ship a refreshed
// theme.
//
// The theme is activated *per session* via `claude --settings <inline-json>`
// from TerminalClaudeSession.shellSpawnArgs — NOT by writing to the global
// ~/.claude/settings.json. That keeps the user's own claude terminal on the
// user's own theme. Earlier Plumage builds did write the global key; on boot
// we strip it back out via removeManagedThemeFromSettings so users return to
// whatever they had before (or to claude's default).
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
    // ~/.claude/themes/<name>.json keeps its bare name; only the settings
    // value gets the prefix. Verified against claude 2.1.150 by selecting
    // "plumage (custom)" through `/theme` and reading back the stored value.
    static let settingsThemeValue = "custom:\(themeName)"
    static let bundledResource = "plumage-theme"
    static let bundledExtension = "json"
    // Inline JSON passed via `claude --settings '<json>'` to scope the theme
    // to a single Plumage-spawned session without touching the user's global
    // ~/.claude/settings.json. Single quotes and newlines are excluded so
    // shellQuotedAttachArgs can wrap the value with a single pair of quotes.
    static let perSessionSettingsJSON = #"{"theme":"custom:plumage"}"#

    static func installIfNeeded(bundle: Bundle = .main, fileManager: FileManager = .default) {
        do {
            guard
                let sourceURL = bundle.url(
                    forResource: bundledResource, withExtension: bundledExtension)
            else { throw InstallError.bundleResourceMissing }
            try writeThemeFile(sourceURL: sourceURL, fileManager: fileManager)
            try removeManagedThemeFromSettings(fileManager: fileManager)
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

    // One-shot migration of earlier Plumage builds: they wrote
    // `"theme":"custom:plumage"` (or the legacy bare `"plumage"`) into the
    // user's global ~/.claude/settings.json, which leaked the Plumage look
    // into the user's own claude terminal. Now that the theme is injected
    // per-session via --settings, strip our managed value back out. Touch
    // ONLY the theme key — settings.json is shared state owned by claude
    // (api_key_helper, permissions, model, …); leave everything else as-is,
    // and bail on anything we can't safely parse rather than clobber.
    static func removeManagedThemeFromSettings(
        fileManager: FileManager = .default,
        settingsURL: URL? = nil
    ) throws {
        let url = try settingsURL ?? defaultSettingsFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
            var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        guard let current = json["theme"] as? String,
            current == settingsThemeValue || current == themeName
        else { return }
        json.removeValue(forKey: "theme")
        let updated = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: url, options: .atomic)
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
