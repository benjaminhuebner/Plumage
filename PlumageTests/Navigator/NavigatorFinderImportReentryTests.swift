import Foundation
import Testing

@testable import Plumage

// Finder import into the project tree must be repeatable and land in the targeted folder:
// the first-drop-only defect lived in the view layer (the outline went deaf after a reload's
// relayout), not here. This pins the model contract the overlay fix relies on.
@MainActor
@Suite("Navigator Finder-import re-entry")
struct NavigatorFinderImportReentryTests {
    private final class Fixture {
        let root: URL
        let source: URL

        init() throws {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("NavImport-\(UUID().uuidString)", isDirectory: true)
            root = base.appendingPathComponent("project", isDirectory: true)
            source = base.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }

        @discardableResult
        func makeFolder(_ relativePath: String) throws -> URL {
            let url = root.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func makeSource(_ name: String) throws -> URL {
            let url = source.appendingPathComponent(name)
            try Data("hello".utf8).write(to: url)
            return url
        }
    }

    private func contains(_ nodes: [FileNode], relativePath: String) -> Bool {
        for node in nodes {
            if node.relativePath == relativePath { return true }
            if let children = node.children, contains(children, relativePath: relativePath) {
                return true
            }
        }
        return false
    }

    @Test("a second Finder import in the same session lands in its targeted folder")
    func repeatedTargetedImports() async throws {
        let fixture = try Fixture()
        let folderA = try fixture.makeFolder(".claude/A")
        let folderB = try fixture.makeFolder(".claude/B")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        let first = try fixture.makeSource("first.md")
        await model.handleFinderDrop(urls: [first], targetFolder: folderA, projectURL: fixture.root)
        #expect(FileManager.default.fileExists(atPath: folderA.appendingPathComponent("first.md").path))
        #expect(contains(model.rootNodes, relativePath: ".claude/A/first.md"))

        // The exact symptom of the fixed defect: the second drop did nothing. It must land now,
        // and in a *different* targeted folder.
        let second = try fixture.makeSource("second.md")
        await model.handleFinderDrop(urls: [second], targetFolder: folderB, projectURL: fixture.root)
        #expect(FileManager.default.fileExists(atPath: folderB.appendingPathComponent("second.md").path))
        #expect(contains(model.rootNodes, relativePath: ".claude/B/second.md"))
        #expect(contains(model.rootNodes, relativePath: ".claude/A/first.md"))
    }

    @Test("import is rejected outside the whitelisted subtree")
    func importOutsideWhitelistRejected() async throws {
        let fixture = try Fixture()
        try fixture.makeFolder(".claude")
        // Exists but lives outside .claude — a legal-looking yet invalid target.
        let outside = try fixture.makeFolder("outside")
        let model = NavigatorModel()
        await model.reload(projectURL: fixture.root)

        let stray = try fixture.makeSource("stray.md")
        await model.handleFinderDrop(urls: [stray], targetFolder: outside, projectURL: fixture.root)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("stray.md").path))
        #expect(model.dropRejectMessage != nil)
    }
}
