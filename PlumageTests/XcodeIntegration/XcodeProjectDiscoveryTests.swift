import Foundation
import Testing

@testable import Plumage

@Suite("XcodeProjectDiscovery")
struct XcodeProjectDiscoveryTests {
    @Test("returns nil when no Xcode artifacts are present")
    func returnsNilForEmptyDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeFile("README.md", in: dir, content: "# nothing here")

        #expect(XcodeProjectDiscovery.find(in: dir) == nil)
    }

    @Test("finds a single .xcodeproj at the root")
    func findsLoneProject() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let found = try #require(XcodeProjectDiscovery.find(in: dir))
        #expect(found.kind == .project)
        #expect(found.url.lastPathComponent == "MyApp.xcodeproj")
        #expect(found.listFlag == "-project")
    }

    @Test("prefers .xcworkspace over .xcodeproj when both exist")
    func prefersWorkspace() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("MyApp.xcodeproj")
        let ws = dir.appendingPathComponent("MyApp.xcworkspace")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)

        let found = try #require(XcodeProjectDiscovery.find(in: dir))
        #expect(found.kind == .workspace)
        #expect(found.url.lastPathComponent == "MyApp.xcworkspace")
        #expect(found.listFlag == "-workspace")
    }

    @Test("picks alphabetically first project when multiple exist")
    func picksAlphabeticallyFirst() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zproj = dir.appendingPathComponent("Zeta.xcodeproj")
        let aproj = dir.appendingPathComponent("Alpha.xcodeproj")
        try FileManager.default.createDirectory(at: zproj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aproj, withIntermediateDirectories: true)

        let found = try #require(XcodeProjectDiscovery.find(in: dir))
        #expect(found.url.lastPathComponent == "Alpha.xcodeproj")
    }

    @Test("findAll returns workspaces first, then projects, both sorted")
    func findAllOrdering() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Zeta.xcodeproj"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Alpha.xcodeproj"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Workspace.xcworkspace"),
            withIntermediateDirectories: true)

        let all = XcodeProjectDiscovery.findAll(in: dir)
        #expect(all.map(\.displayName) == ["Workspace.xcworkspace", "Alpha.xcodeproj", "Zeta.xcodeproj"])
    }

    @Test("returns nil when directory does not exist")
    func nilForMissingDirectory() {
        let bogus = URL(fileURLWithPath: "/nonexistent-plumage-probe-\(UUID().uuidString)")
        #expect(XcodeProjectDiscovery.find(in: bogus) == nil)
        #expect(XcodeProjectDiscovery.findAll(in: bogus).isEmpty)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageXcodeDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ name: String, in dir: URL, content: String) throws {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
