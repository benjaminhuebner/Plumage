import Foundation
import Testing

@testable import Plumage

// End-to-end acceptance: scaffold real projects on disk and prove they open
// through the existing open path (`BundleResolver` + `ConfigLoader`), with the
// per-kind content, hook, config and git artifacts the spec requires.
@Suite("New project engine acceptance")
struct NewProjectEngineAcceptanceTests {
    private let fileManager = FileManager.default

    private func scaffolder() -> ProjectScaffolder {
        ProjectScaffolder(
            assetsRoot: RepoAssets.root,
            overrideRoot: nil,
            configCreator: ProjectConfigCreator(createdWithPlumageVersion: "9.9.9"))
    }

    // Returns the project root inside a unique parent; caller defers removal of `parent`.
    private func freshRoot() -> (root: URL, parent: URL) {
        let parent = fileManager.temporaryDirectory
            .appending(path: "Acceptance-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (parent.appending(path: "Acme", directoryHint: .isDirectory), parent)
    }

    private func configJSON(_ bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appending(path: "config.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test(
        "Every kind scaffolds a project that opens via BundleResolver + ConfigLoader",
        arguments: ProjectKind.allCases)
    func opensForEveryKind(_ kind: ProjectKind) async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }

        let created = try await scaffolder().create(
            spec: NewProjectSpec(kind: kind, name: "Acme", tagline: "An app", projectDirectory: root))

        // The existing open path must accept the result unchanged.
        let resolved = try BundleResolver.resolve(from: created.root)
        let config = try ConfigLoader.load(atBundle: resolved.bundle)
        #expect(config.name == "Acme")
        #expect(config.schemaVersion <= SchemaVersion.current)

        let obj = try configJSON(resolved.bundle)
        #expect(obj["projectType"] as? String == kind.rawValue)
        #expect((obj["issueIdPadding"] as? Int ?? 0) >= 1)
    }

    @Test("CLAUDE.md carries kind-correct sections; .other has none")
    func claudeMdContent() async throws {
        func claudeMd(_ kind: ProjectKind) async throws -> String {
            let (root, parent) = freshRoot()
            defer { try? fileManager.removeItem(at: parent) }
            let created = try await scaffolder().create(
                spec: NewProjectSpec(kind: kind, name: "Acme", tagline: "x", projectDirectory: root))
            return try String(contentsOf: created.root.appending(path: ".claude/CLAUDE.md"), encoding: .utf8)
        }
        let mac = try await claudeMd(.macOS)
        #expect(mac.contains("Liquid Glass"))  // apple-shared pitfall
        #expect(mac.contains("Strict concurrency"))  // swift-shared convention
        #expect(!mac.contains("<<<"))

        let other = try await claudeMd(.other)
        #expect(!other.contains("Liquid Glass"))
        #expect(!other.contains("Strict concurrency"))
        #expect(!other.contains("<<<"))
    }

    @Test(
        "Hook set on disk matches the profile and every hook is executable",
        arguments: ProjectKind.allCases)
    func hooksMatchProfileAndExecutable(_ kind: ProjectKind) async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(kind: kind, name: "Acme", tagline: "x", projectDirectory: root))

        let hooksDir = created.root.appending(path: ".claude/hooks")
        let files = try fileManager.contentsOfDirectory(atPath: hooksDir.path)
        let names = Set(files.map { $0.replacingOccurrences(of: ".sh", with: "") })
        #expect(names == Set(kind.profile.hookNames))
        for file in files {
            let perms =
                try fileManager.attributesOfItem(atPath: hooksDir.appending(path: file).path)[
                    .posixPermissions] as? Int
            #expect(((perms ?? 0) & 0o111) != 0, "\(file) not executable")
        }
    }

    @Test("Swift kinds get .swift-format + .swiftlint.yml; .other does not")
    func swiftConfigsPresence() async throws {
        for kind in ProjectKind.allCases {
            let (root, parent) = freshRoot()
            defer { try? fileManager.removeItem(at: parent) }
            let created = try await scaffolder().create(
                spec: NewProjectSpec(kind: kind, name: "Acme", tagline: "x", projectDirectory: root))
            let hasFormat = fileManager.fileExists(atPath: created.root.appending(path: ".swift-format").path)
            let hasLint = fileManager.fileExists(atPath: created.root.appending(path: ".swiftlint.yml").path)
            #expect(hasFormat == kind.isSwift)
            #expect(hasLint == kind.isSwift)
        }
    }

    @Test("Requested .gitignore always carries the macOS block; Swift kinds the Swift/Xcode block")
    func gitignoreContent() async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "x", projectDirectory: root,
                git: GitSetup(createGitignore: true)))
        let ignore = try String(contentsOf: created.root.appending(path: ".gitignore"), encoding: .utf8)
        #expect(ignore.contains(".DS_Store"))  // macOS, always
        #expect(ignore.contains("DerivedData/"))  // xcode
        #expect(ignore.contains(".build/"))  // swift
        // Plumage's ephemeral state lives in .git/info/exclude, never the shared .gitignore.
        #expect(!ignore.contains(".plumage/"))
    }

    @Test("git exclude: committed bundle (plumageInGit) excludes only the ephemeral subfolders")
    func gitExcludeEphemeral() async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "x", projectDirectory: root,
                git: GitSetup(plumageInGit: true, createGitignore: true)))
        let exclude = try String(
            contentsOf: created.root.appending(path: ".git/info/exclude"), encoding: .utf8)
        let excludeLines = exclude.split(separator: "\n").map(String.init)
        #expect(excludeLines.contains("*.plumage/runs/"))
        #expect(excludeLines.contains("*.plumage/sessions/"))
        #expect(!excludeLines.contains("Acme.plumage/"))  // bundle itself stays tracked
    }

    @Test("git exclude: plumageInGit=false excludes plumage dirs; claudeInGit=false excludes claude + mcp")
    func gitExcludeVariants() async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(
                kind: .macOS, name: "Acme", tagline: "x", projectDirectory: root,
                git: GitSetup(plumageInGit: false, claudeInGit: false, createGitignore: true)))
        let exclude = try String(
            contentsOf: created.root.appending(path: ".git/info/exclude"), encoding: .utf8)
        let excludeLines = exclude.split(separator: "\n").map(String.init)
        // The whole bundle is excluded; the obsolete `.plumage/` dotfolder is
        // no longer created, so it must not be excluded as a standalone line
        // (substring-matching `.plumage/` would falsely pass via `Acme.plumage/`).
        #expect(excludeLines.contains("Acme.plumage/"))
        #expect(!excludeLines.contains(".plumage/"))
        // Whole bundle is excluded, so the ephemeral-subfolder lines are redundant.
        #expect(!excludeLines.contains("*.plumage/runs/"))
        #expect(excludeLines.contains(".claude/"))
        #expect(excludeLines.contains(".mcp.json"))
    }

    @Test("config.json reflects projectType and git.agentFilesInGit")
    func configReflectsGitChoice() async throws {
        let (root, parent) = freshRoot()
        defer { try? fileManager.removeItem(at: parent) }
        let created = try await scaffolder().create(
            spec: NewProjectSpec(
                kind: .vapor, name: "Acme", tagline: "x", projectDirectory: root,
                git: GitSetup(claudeInGit: false)))
        let obj = try configJSON(created.bundle)
        #expect(obj["projectType"] as? String == "vapor")
        let git = try #require(obj["git"] as? [String: Any])
        #expect(git["agentFilesInGit"] as? Bool == false)
    }
}
