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

    @Test("ensureSettingsTheme sets theme when absent")
    func setsThemeWhenAbsent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try "{}".write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] as? String == "plumage")
    }

    @Test("ensureSettingsTheme preserves user's non-plumage theme choice")
    func preservesUserTheme() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try #"{"theme": "dark-daltonized", "other": "value"}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] as? String == "dark-daltonized")
        #expect(json["other"] as? String == "value")
    }

    @Test("ensureSettingsTheme creates settings file when missing")
    func createsSettingsWhenMissing() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] as? String == "plumage")
    }

    @Test("ensureSettingsTheme leaves an unparseable settings.json untouched")
    func bailsOnCorruptSettings() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        // settings.json is owned by claude (api_key_helper, permissions, model,
        // …). If JSONSerialization can't parse it (BOM, trailing commas from
        // another tool, hand-edit), we must NOT silently overwrite — that
        // would destroy unrelated config. The installer should bail.
        let corrupt = "not valid { json } # with comment"
        try corrupt.write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let after = try String(contentsOf: settings, encoding: .utf8)
        #expect(after == corrupt)
    }

    @Test("ensureSettingsTheme leaves a JSON-array settings.json untouched")
    func bailsOnNonDictRoot() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        // Valid JSON but not a dict at the root — same bail-out path: don't
        // overwrite something we can't safely merge into.
        let arrayRoot = "[\"foo\", \"bar\"]"
        try arrayRoot.write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let after = try String(contentsOf: settings, encoding: .utf8)
        #expect(after == arrayRoot)
    }

    @Test("ensureSettingsTheme re-syncs existing plumage theme entry")
    func resyncsPlumageEntry() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = tmp.appendingPathComponent("settings.json")
        try #"{"theme": "plumage", "untouched": true}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        try ClaudeThemeInstaller.ensureSettingsTheme(settingsURL: settings)

        let data = try Data(contentsOf: settings)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] as? String == "plumage")
        #expect(json["untouched"] as? Bool == true)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeThemeInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
