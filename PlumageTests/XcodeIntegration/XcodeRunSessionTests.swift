import Foundation
import Testing

@testable import Plumage

@Suite("ProductionAppLauncher")
struct ProductionAppLauncherTests {
    @Test("openApp passes -n to /usr/bin/open for a fresh instance")
    func openPassesDashN() async throws {
        let mock = MockXcodeProcessRunner()
        let launcher = ProductionAppLauncher(runner: mock)
        try await launcher.openApp(at: URL(fileURLWithPath: "/tmp/Build/Demo.app"))
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.binaryURL.path == "/usr/bin/open")
        #expect(invocation.args == ["-n", "/tmp/Build/Demo.app"])
    }

    @Test("openApp throws on non-zero exit")
    func openSurfacesNonZeroExit() async {
        let mock = MockXcodeProcessRunner()
        mock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 1, stdout: Data(),
                stderr: Data("not a bundle".utf8)
            ))
        let launcher = ProductionAppLauncher(runner: mock)
        do {
            try await launcher.openApp(at: URL(fileURLWithPath: "/tmp/Build/Demo.app"))
            Issue.record("expected non-zero exit to throw")
        } catch let error as XcodeProcessRunnerError {
            if case .nonZeroExit = error {
                // expected
            } else {
                Issue.record("unexpected error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

@Suite("XcodeRunSession (macOS)")
struct XcodeRunSessionMacTests {
    @Test("launches the macOS bundle via the app launcher on a green build")
    func macHappyPath() async throws {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: ["compiling"], exitCode: 0)
        buildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 0,
                stdout: Data(
                    """
                    Build settings from command line:
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
        let launcher = RecordingAppLauncher()
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: MockXcodeProcessRunner(),
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }),
            appLauncher: launcher
        )
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "platform=macOS",
            isSimulatorDestination: false,
            simulatorUDID: nil
        )
        let collected = LineCollector()
        let outcome = await session.run(inputs: inputs, onLine: { collected.append($0) })
        #expect(outcome == .launched)
        #expect(launcher.openedURLs.map(\.path) == ["/tmp/Build/Demo.app"])
        #expect(collected.lines == ["compiling"])
    }

    @Test("build failure surfaces as .buildFailed")
    func buildFailureSurfaces() async {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: ["error"], exitCode: 65)
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
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "platform=macOS",
            isSimulatorDestination: false,
            simulatorUDID: nil
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .buildFailed(let code) = outcome {
            #expect(code == 65)
        } else {
            Issue.record("expected .buildFailed, got \(outcome)")
        }
    }

    @Test("missing build settings surface as launchFailed")
    func missingBuildSettings() async {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: [], exitCode: 0)
        buildMock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: Data(), stderr: Data())
        )
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
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "platform=macOS",
            isSimulatorDestination: false,
            simulatorUDID: nil
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .launchFailed = outcome {
            // expected
        } else {
            Issue.record("expected .launchFailed, got \(outcome)")
        }
    }
}

// Sendable launcher mock used by the macOS tests above.
final class RecordingAppLauncher: AppLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []

    var openedURLs: [URL] {
        lock.withLock { _opened }
    }

    func openApp(at url: URL) async throws {
        lock.withLock { _opened.append(url) }
    }
}
