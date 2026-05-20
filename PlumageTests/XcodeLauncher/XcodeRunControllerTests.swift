import Foundation
import Testing

@testable import Plumage

@MainActor
@Suite("XcodeRunController")
struct XcodeRunControllerTests {
    @Test("startRun is a no-op when scheme or destination is missing")
    func startNoopWhenIncomplete() async {
        let model = XcodeRunModel()
        let controller = XcodeRunController(model: model)
        controller.startRun()
        #expect(model.runState == .idle)
        #expect(controller.runTask == nil)
    }

    @Test("startRun flips state through building → running on a green build")
    func happyPathTransitions() async throws {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: [], exitCode: 0)
        buildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 0,
                stdout: Data(
                    """
                    BUILT_PRODUCTS_DIR = /tmp/Build
                    FULL_PRODUCT_NAME = Demo.app
                    PRODUCT_BUNDLE_IDENTIFIER = com.example.demo
                    """.utf8),
                stderr: Data()
            ))
        let xcodebuild = XcodebuildRunner(
            runner: buildMock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )
        let appLauncher = RecordingAppLauncher()
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: MockXcodeProcessRunner(),
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }),
            appLauncher: appLauncher
        )
        let stub = await stubbedModel()
        defer { try? FileManager.default.removeItem(at: stub.tempDir) }
        let controller = XcodeRunController(model: stub.model, runSession: session)

        controller.startRun()
        #expect(stub.model.runState == .building)
        await controller.runTask?.value
        #expect(stub.model.runState == .running)
        #expect(appLauncher.openedURLs.map(\.path) == ["/tmp/Build/Demo.app"])
    }

    @Test("failed build flips state to .failed with a message")
    func failurePath() async throws {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(
            lines: ["file.swift:1:1: error: bad code"], exitCode: 65)
        let xcodebuild = XcodebuildRunner(
            runner: buildMock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: MockXcodeProcessRunner(),
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }),
            appLauncher: RecordingAppLauncher()
        )
        let stub = await stubbedModel()
        defer { try? FileManager.default.removeItem(at: stub.tempDir) }
        let controller = XcodeRunController(model: stub.model, runSession: session)

        controller.startRun()
        await controller.runTask?.value
        if case .failed = stub.model.runState {
            // expected
        } else {
            Issue.record("expected .failed, got \(stub.model.runState)")
        }
    }

    @Test("cancelRun resets state to idle")
    func cancelResetsState() async throws {
        let stub = await stubbedModel()
        defer { try? FileManager.default.removeItem(at: stub.tempDir) }
        let controller = XcodeRunController(model: stub.model)
        stub.model.setRunState(.building)
        controller.cancelRun()
        #expect(stub.model.runState == .idle)
    }

    @MainActor
    private func stubbedModel() async -> (model: XcodeRunModel, tempDir: URL) {
        // Build a model that "discovered" a project so startRun has all it needs.
        let listJSON =
            """
            {
              "project": { "name": "Plumage", "schemes": ["Plumage"] }
            }
            """
        let simJSON = """
            { "devices": {} }
            """
        let xcodebuildMock = MockXcodeProcessRunner()
        xcodebuildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: Data(listJSON.utf8), stderr: Data())
        )
        let simMock = MockXcodeProcessRunner()
        simMock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: Data(simJSON.utf8), stderr: Data())
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageXcodeRun-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let proj = dir.appendingPathComponent("Demo.xcodeproj")
        try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let model = XcodeRunModel(
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
        return (model, dir)
    }
}
