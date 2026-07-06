import Foundation
import Testing

@testable import Plumage

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
        if case .launched = outcome {
        } else {
            Issue.record("expected .launched, got \(outcome)")
        }
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

// @unchecked Sendable: all mutable state sits behind the NSLock — the lock,
// not the type shape, provides the concurrency safety.
final class RecordingAppLauncher: AppLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [URL] = []

    var openedURLs: [URL] {
        lock.withLock { _opened }
    }

    func openApp(at url: URL) async throws -> Int32? {
        lock.withLock {
            _opened.append(url)
            return 99_999
        }
    }
}
