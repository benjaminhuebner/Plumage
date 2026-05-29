import Foundation
import Testing

@testable import Plumage

@Suite("SettingsComposer")
struct SettingsComposerTests {
    private let composer = SettingsComposer()

    private func settings(_ kind: ProjectKind) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: composer.settingsJSON(for: kind)) as? [String: Any])
    }

    private func hookNames(_ obj: [String: Any]) throws -> Set<String> {
        let hooks = try #require(obj["hooks"] as? [String: Any])
        var names: Set<String> = []
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                for cmd in group["hooks"] as? [[String: Any]] ?? [] {
                    if let command = cmd["command"] as? String,
                        let last = command.split(separator: "/").last
                    {
                        names.insert(String(last).replacingOccurrences(of: ".sh", with: ""))
                    }
                }
            }
        }
        return names
    }

    private func permissions(_ obj: [String: Any]) throws -> [String] {
        let perms = try #require(obj["permissions"] as? [String: Any])
        return try #require(perms["allow"] as? [String])
    }

    @Test("Hook set matches the profile exactly, for every kind")
    func hookSetMatchesProfile() throws {
        for kind in ProjectKind.allCases {
            #expect(try hookNames(try settings(kind)) == Set(kind.profile.hookNames), "mismatch for \(kind)")
        }
    }

    @Test("macOS: guard-xcodebuild + swift hooks + xcodebuild permission")
    func macOS() throws {
        let obj = try settings(.macOS)
        let names = try hookNames(obj)
        #expect(names.contains("guard-xcodebuild"))
        #expect(names.contains("format-swift"))
        #expect(try permissions(obj).contains("Bash(xcodebuild:*)"))
    }

    @Test("Vapor: no guard-xcodebuild; swift build permission, not xcodebuild")
    func vapor() throws {
        let obj = try settings(.vapor)
        #expect(!(try hookNames(obj).contains("guard-xcodebuild")))
        #expect(try hookNames(obj).contains("format-swift"))
        let perms = try permissions(obj)
        #expect(perms.contains("Bash(swift build:*)"))
        #expect(!perms.contains("Bash(xcodebuild:*)"))
    }

    @Test(".other: only workflow hooks, no Swift tooling permissions")
    func other() throws {
        let obj = try settings(.other)
        let names = try hookNames(obj)
        #expect(names.contains("force-plumage-skill"))
        #expect(names.contains("stop-after-spec-approved"))
        #expect(!names.contains("format-swift"))
        #expect(!names.contains("guard-xcodebuild"))
        let perms = try permissions(obj)
        #expect(!perms.contains("Bash(swift-format:*)"))
        #expect(!perms.contains("Bash(xcodebuild:*)"))
        #expect(perms.contains("Bash(git status:*)"))
    }

    @Test("settings.local.json is minimal valid JSON")
    func localSettings() throws {
        let obj = try JSONSerialization.jsonObject(with: composer.localSettingsJSON()) as? [String: Any]
        #expect(obj?.isEmpty == true)
    }
}
