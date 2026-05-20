import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("XcodeRunModel")
struct XcodeRunModelTests {
    @Test("discover yields .noProject when the dir has no Xcode artefacts")
    func discoversNoProject() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = await makeModel(stubProject: false)
        await model.discover(projectURL: dir)
        #expect(model.discoveryState == .noProject)
        #expect(model.projectRef == nil)
    }

    @Test("discover collects schemes and a default destination")
    func discoversProjectWithSchemes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let model = await makeModel()
        await model.discover(projectURL: dir)
        #expect(model.discoveryState == .ready)
        #expect(model.projectRef?.kind == .project)
        #expect(model.schemes == ["Plumage", "PlumageTests"])
        #expect(model.selectedScheme == "Plumage")
        #expect(model.selectedDestination == .myMac)
    }

    @Test("discover surfaces a missing toolchain state")
    func missingToolchain() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let model = await XcodeRunModel(
            xcodebuildRunner: XcodebuildRunner(
                runner: MockXcodeProcessRunner(),
                toolchain: { nil }),
            simulatorCatalog: SimulatorCatalog(
                runner: MockXcodeProcessRunner(),
                toolchain: { nil }),
            xcodebuildLocator: { nil },
            xcrunLocator: { nil }
        )
        await model.discover(projectURL: dir)
        #expect(model.discoveryState == .missingToolchain)
        #expect(model.toolchainAvailable == false)
    }

    @Test("selectScheme accepts known names and ignores unknown ones")
    func selectScheme() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let model = await makeModel()
        await model.discover(projectURL: dir)
        model.selectScheme("PlumageTests")
        #expect(model.selectedScheme == "PlumageTests")
        model.selectScheme("Bogus")
        #expect(model.selectedScheme == "PlumageTests")
    }

    @Test("selectDestination accepts a known sim and rejects an unknown udid")
    func selectDestination() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let model = await makeModel()
        await model.discover(projectURL: dir)
        // simctl fixture's iOS-26-5 group has iPad Pro 13 + iPhone 17 Pro available.
        let sim: XcodeDestination = .simulator(
            udid: "AAAA1111-1111-1111-1111-111111111111",
            name: "iPhone 17 Pro",
            runtimeDisplayName: "iOS 26.5"
        )
        model.selectDestination(sim)
        #expect(model.selectedDestination == sim)

        let bogus: XcodeDestination = .simulator(
            udid: "DEAD-BEEF", name: "?", runtimeDisplayName: "?")
        model.selectDestination(bogus)
        #expect(model.selectedDestination == sim)
    }

    @Test("restoreSelections rehydrates persisted scheme and simulator")
    func restoreSelections() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let model = await makeModel()
        await model.discover(projectURL: dir)
        model.restoreSelections(
            scheme: "PlumageTests",
            destinationID: "sim:AAAA1111-1111-1111-1111-222222222222"
        )
        #expect(model.selectedScheme == "PlumageTests")
        if case .simulator(_, let name, _) = model.selectedDestination {
            #expect(name == "iPad Pro 13")
        } else {
            Issue.record("expected simulator destination")
        }
    }

    @Test("log buffer caps at logCap entries")
    func logCap() async {
        let model = await makeModel(stubProject: false)
        for index in 0..<(XcodeRunModel.logCap + 50) {
            model.appendLog("line \(index)")
        }
        #expect(model.logBuffer.count == XcodeRunModel.logCap)
        #expect(model.tailLog.count == XcodeRunModel.logTail)
    }

    @Test("discover surfaces a parse error from xcodebuild as .failed")
    func failedListSchemes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        let xcodebuildMock = MockXcodeProcessRunner()
        xcodebuildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 0,
                stdout: Data("invalid".utf8),
                stderr: Data()
            ))
        let simMock = MockXcodeProcessRunner()
        let model = await XcodeRunModel(
            xcodebuildRunner: XcodebuildRunner(
                runner: xcodebuildMock,
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }),
            simulatorCatalog: SimulatorCatalog(
                runner: simMock,
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }),
            xcodebuildLocator: { URL(fileURLWithPath: "/usr/bin/xcodebuild") },
            xcrunLocator: { URL(fileURLWithPath: "/usr/bin/xcrun") }
        )
        await model.discover(projectURL: dir)
        if case .failed = model.discoveryState {
            // expected
        } else {
            Issue.record("expected .failed, got \(model.discoveryState)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel(stubProject: Bool = true) -> XcodeRunModel {
        let listJSON = try? loadFixture("list-project.json")
        let simJSON = try? loadFixture("simctl-devices.json")
        let xcodebuildMock = MockXcodeProcessRunner()
        xcodebuildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 0,
                stdout: listJSON ?? Data(),
                stderr: Data()
            ))
        let simMock = MockXcodeProcessRunner()
        simMock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 0,
                stdout: simJSON ?? Data(),
                stderr: Data()
            ))
        return XcodeRunModel(
            xcodebuildRunner: XcodebuildRunner(
                runner: xcodebuildMock,
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }),
            simulatorCatalog: SimulatorCatalog(
                runner: simMock,
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }),
            xcodebuildLocator: { URL(fileURLWithPath: "/usr/bin/xcodebuild") },
            xcrunLocator: { URL(fileURLWithPath: "/usr/bin/xcrun") }
        )
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageXcodeRun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadFixture(_ name: String) throws -> Data {
        // Fixtures live under PlumageTests/XcodeIntegration/Fixtures/.
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()  // XcodeLauncher/
            .deletingLastPathComponent()  // PlumageTests/
            .appending(path: "XcodeIntegration/Fixtures/\(name)")
        return try Data(contentsOf: url)
    }
}
