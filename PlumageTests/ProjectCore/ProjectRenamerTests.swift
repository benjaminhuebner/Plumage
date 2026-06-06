import Foundation
import Testing

@testable import Plumage

@Suite("ProjectRenamer.rename")
struct ProjectRenamerTests {
    private func makeProject(
        bundleName: String = "Test",
        configName: String = "Test"
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageRenamer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = root.appendingPathComponent("\(bundleName).plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let config = """
            {
              "name": "\(configName)",
              "schemaVersion": 2,
              "issueIdPadding": 5,
              "git": { "defaultBranch": "main" }
            }
            """
        try config.write(
            to: bundle.appendingPathComponent("config.json"),
            atomically: true, encoding: .utf8)
        return root
    }

    @Test("moves the bundle folder and rewrites config.name")
    func happyPath() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let newBundle = try ProjectRenamer.rename(projectRoot: root, newName: "Renamed")

        #expect(newBundle.lastPathComponent == "Renamed.plumage")
        #expect(FileManager.default.fileExists(atPath: newBundle.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Test.plumage").path))

        let reloaded = try ConfigLoader.load(at: root)
        #expect(reloaded.name == "Renamed")
        // Sibling keys survive the rename.
        #expect(reloaded.schemaVersion == 2)
        #expect(reloaded.issueIdPadding == 5)
        #expect(reloaded.git?.defaultBranch == "main")
    }

    @Test("trims surrounding whitespace from the new name")
    func trimsWhitespace() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let newBundle = try ProjectRenamer.rename(projectRoot: root, newName: "  Renamed  ")

        #expect(newBundle.lastPathComponent == "Renamed.plumage")
        #expect(try ConfigLoader.load(at: root).name == "Renamed")
    }

    @Test("rejects invalid names without touching disk", arguments: ["", "  ", "a/b", ".", ".."])
    func rejectsInvalidNames(_ name: String) throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect {
            try ProjectRenamer.rename(projectRoot: root, newName: name)
        } throws: { error in
            error as? ProjectRenamer.RenameError == .invalidName
        }

        // Original bundle and name are untouched.
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Test.plumage").path))
        #expect(try ConfigLoader.load(at: root).name == "Test")
    }

    @Test("folder already named correctly but config.name drifted: rewrites name, no move")
    func legacyFolderNameMatchesConfigDrifted() throws {
        // Mirrors the #00010 case: the user renamed the bundle in Finder, so the
        // folder is `Renamed.plumage` but config.name is still the old value.
        let root = try makeProject(bundleName: "Renamed", configName: "Old")
        defer { try? FileManager.default.removeItem(at: root) }

        let newBundle = try ProjectRenamer.rename(projectRoot: root, newName: "Renamed")

        #expect(newBundle.lastPathComponent == "Renamed.plumage")
        #expect(FileManager.default.fileExists(atPath: newBundle.path))
        #expect(try ConfigLoader.load(at: root).name == "Renamed")
    }

    @Test("two bundles in the root fail safely without moving anything")
    func multipleBundlesFailSafely() throws {
        let root = try makeProject(bundleName: "Test", configName: "Test")
        defer { try? FileManager.default.removeItem(at: root) }
        // A second bundle makes BundleResolver.findBundle ambiguous; the rename
        // must refuse rather than guess which one to move.
        let second = root.appendingPathComponent("Other.plumage", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        #expect {
            try ProjectRenamer.rename(projectRoot: root, newName: "Renamed")
        } throws: { error in
            guard case .resolveFailed = error as? ProjectRenamer.RenameError else { return false }
            return true
        }

        // Neither bundle moved.
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Test.plumage").path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed.plumage").path))
    }

    @Test("no bundle in the root fails with resolveFailed")
    func noBundleFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageRenamer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect {
            try ProjectRenamer.rename(projectRoot: root, newName: "Renamed")
        } throws: { error in
            guard case .resolveFailed = error as? ProjectRenamer.RenameError else { return false }
            return true
        }
    }
}
