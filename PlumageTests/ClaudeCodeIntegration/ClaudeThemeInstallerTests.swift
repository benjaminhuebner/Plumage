import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeThemeInstaller")
struct ClaudeThemeInstallerTests {
    @Test("writeThemeFile copies source JSON to the destination atomically")
    func writeCopiesSource() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let source = tmp.appendingPathComponent("source.json")
        let payload = #"{"name":"plumage","base":"dark-ansi","overrides":{"background":"transparent"}}"#
        try payload.write(to: source, atomically: true, encoding: .utf8)
        let dest = tmp.appendingPathComponent("themes/plumage.json")

        try ClaudeThemeInstaller.writeThemeFile(sourceURL: source, destination: dest)

        let data = try Data(contentsOf: dest)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["name"] as? String == "plumage")
        let overrides = try #require(json["overrides"] as? [String: Any])
        #expect(overrides["background"] as? String == "transparent")
    }

    @Test("perSessionSettingsJSON carries the appearance-matched custom theme value")
    func perSessionJSONShape() throws {
        for (dark, expected) in [(true, "custom:plumage"), (false, "custom:plumage-light")] {
            let raw = ClaudeThemeInstaller.perSessionSettingsJSON(dark: dark)
            let data = try #require(raw.data(using: .utf8))
            let json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            // claude requires the `custom:` prefix — bare "plumage" is silently
            // treated as an unknown built-in and falls back to "Dark mode".
            #expect(json["theme"] as? String == expected)
            // Must stay free of characters that would break single-quote shell
            // wrapping in TerminalClaudeSession.shellQuotedAttachArgs.
            #expect(!raw.contains("'"))
            #expect(!raw.contains("\n"))
        }
    }

    @Test("perSessionSettingsJSON pins promptSuggestionEnabled=false")
    func perSessionDisablesPromptSuggestions() throws {
        for dark in [true, false] {
            let data = try #require(
                ClaudeThemeInstaller.perSessionSettingsJSON(dark: dark).data(using: .utf8))
            let json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            // claude defaults `promptSuggestionEnabled` to true and renders a
            // "Predicted next user prompt" line after every turn. Plumage opts out
            // per-session so the embedded terminal matches a user's suggestion-
            // free Terminal.app setup without writing to ~/.claude/settings.json.
            #expect(json["promptSuggestionEnabled"] as? Bool == false)
        }
    }

    @Test("removeManagedThemeFromSettings strips custom:plumage and leaves siblings alone")
    func removesCustomPlumage() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try #"{"theme": "custom:plumage", "model": "sonnet", "untouched": true}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The theme key is gone entirely so claude falls back to whatever
        // default it picks for the user's own terminal.
        #expect(json["theme"] == nil)
        // Unrelated keys must survive — settings.json is shared state owned
        // by claude (api_key_helper, permissions, model, …).
        #expect(json["model"] as? String == "sonnet")
        #expect(json["untouched"] as? Bool == true)
    }

    @Test("removeManagedThemeFromSettings strips legacy bare 'plumage' value")
    func removesLegacyBareValue() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        // Pre-`custom:` Plumage builds wrote the bare name. Treat it as ours
        // and migrate it out the same way.
        try #"{"theme": "plumage", "other": "value"}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] == nil)
        #expect(json["other"] as? String == "value")
    }

    @Test("removeManagedThemeFromSettings strips the managed light theme value")
    func removesLightValue() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try #"{"theme": "custom:plumage-light", "other": "value"}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] == nil)
        #expect(json["other"] as? String == "value")
    }

    @Test("removeManagedThemeFromSettings preserves a user-chosen non-plumage theme")
    func preservesUserTheme() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try #"{"theme": "dark-daltonized", "other": "value"}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // User picked their own theme — we never overwrite or remove it.
        #expect(json["theme"] as? String == "dark-daltonized")
        #expect(json["other"] as? String == "value")
    }

    @Test("removeManagedThemeFromSettings is a no-op when settings.json has no theme key")
    func noOpWhenThemeAbsent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        let before = #"{"model": "sonnet"}"#
        try before.write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        // No theme key means nothing for us to do — leave the file byte-for-
        // byte intact rather than re-serializing it (which could churn key
        // order or formatting in a way that surprises other tooling).
        let after = try String(contentsOf: settings, encoding: .utf8)
        #expect(after == before)
    }

    @Test("removeManagedThemeFromSettings is a no-op when settings.json does not exist")
    func noOpWhenFileMissing() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        // We never create settings.json — that's claude's job. A fresh
        // install must not produce an empty file as a side effect.
        #expect(!FileManager.default.fileExists(atPath: settings.path))
    }

    @Test("removeManagedThemeFromSettings leaves an unparseable settings.json untouched")
    func bailsOnCorruptSettings() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        // settings.json is owned by claude. If JSONSerialization can't parse
        // it (BOM, trailing commas from another tool, hand-edit), we must
        // NOT silently overwrite — that would destroy unrelated config.
        let corrupt = "not valid { json } # with comment"
        try corrupt.write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let after = try String(contentsOf: settings, encoding: .utf8)
        #expect(after == corrupt)
    }

    @Test("removeManagedThemeFromSettings leaves a JSON-array settings.json untouched")
    func bailsOnNonDictRoot() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        // Valid JSON but not a dict at the root — same bail-out path: don't
        // overwrite something we can't safely merge into.
        let arrayRoot = "[\"foo\", \"bar\"]"
        try arrayRoot.write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.removeManagedThemeFromSettings(settingsURL: settings)

        let after = try String(contentsOf: settings, encoding: .utf8)
        #expect(after == arrayRoot)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeThemeInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
