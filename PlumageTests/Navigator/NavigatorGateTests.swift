import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("NavigatorModel inactive gate")
struct NavigatorGateTests {
    private func makeTempProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nav-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test("defers reloads while inactive and replays exactly one on reactivation")
    func coalescesWhileInactive() async throws {
        let dir = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nav = NavigatorModel()

        var didReload = await nav.reloadOrDefer(projectURL: dir)
        #expect(didReload)
        #expect(nav.reloadGeneration == 1)

        _ = await nav.setActive(false, projectURL: dir)
        didReload = await nav.reloadOrDefer(projectURL: dir)
        #expect(!didReload)
        didReload = await nav.reloadOrDefer(projectURL: dir)
        #expect(!didReload)
        #expect(nav.reloadGeneration == 1)

        let reactivated = await nav.setActive(true, projectURL: dir)
        #expect(reactivated)
        #expect(nav.reloadGeneration == 2)

        _ = await nav.setActive(false, projectURL: dir)
        let reactivatedAgain = await nav.setActive(true, projectURL: dir)
        #expect(!reactivatedAgain)
        #expect(nav.reloadGeneration == 2)
    }
}
