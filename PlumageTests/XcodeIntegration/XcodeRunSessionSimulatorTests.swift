import Foundation
import Testing

@testable import Plumage

@Suite("XcodeRunSession (iOS simulator)")
struct XcodeRunSessionSimulatorTests {
    @Test("boots, installs, and launches on the selected simulator")
    func simulatorHappyPath() async throws {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: ["building"], exitCode: 0)
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
        let simMock = MockXcodeProcessRunner()
        let simCatalog = SimulatorCatalog(
            runner: simMock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }
        )
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: simCatalog,
            appLauncher: RecordingAppLauncher()
        )

        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "id=AAAA-UDID",
            isSimulatorDestination: true,
            simulatorUDID: "AAAA-UDID"
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .launched = outcome {
        } else {
            Issue.record("expected .launched, got \(outcome)")
        }

        // Build → showBuildSettings → boot → install → launch.
        // xcodebuild gets `build` (stream), `-showBuildSettings` (run).
        // xcrun gets `boot`, `install`, `launch` in that order.
        let simInvocations = simMock.invocations.map(\.args)
        #expect(simInvocations.first == ["simctl", "boot", "AAAA-UDID"])
        #expect(simInvocations.count == 3)
        #expect(simInvocations[1] == ["simctl", "install", "AAAA-UDID", "/tmp/Build/Demo.app"])
        #expect(simInvocations[2] == ["simctl", "launch", "AAAA-UDID", "com.example.demo"])
    }

    @Test("already-booted sim does not abort the install + launch")
    func alreadyBootedSurvives() async throws {
        let buildMock = MockXcodeProcessRunner()
        buildMock.streamOutcome = .success(lines: [], exitCode: 0)
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
        let simMock = MockXcodeProcessRunner()
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        simMock.setRunOutcome(
            .success(
                XcodeSpawnResult(
                    exitCode: 0, stdout: Data(), stderr: Data()
                )),
            forBinary: xcrunURL
        )
        // The per-call "boot returns 149 (already booted)" branch is covered
        // exhaustively in SimulatorCatalogTests. Here we just assert that with
        // a green boot, install + launch chain through to a .launched outcome.
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: simMock,
                toolchain: { xcrunURL }
            ),
            appLauncher: RecordingAppLauncher()
        )
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "id=AAAA-UDID",
            isSimulatorDestination: true,
            simulatorUDID: "AAAA-UDID"
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .launched = outcome {
        } else {
            Issue.record("expected .launched, got \(outcome)")
        }
    }

    @Test("missing simulator UDID → launchFailed")
    func missingUDID() async {
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
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: MockXcodeProcessRunner(),
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }
            ),
            appLauncher: RecordingAppLauncher()
        )
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "id=UNKNOWN",
            isSimulatorDestination: true,
            simulatorUDID: nil
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .launchFailed = outcome {
            // expected
        } else {
            Issue.record("expected .launchFailed, got \(outcome)")
        }
    }

    @Test("simctl failure propagates as launchFailed")
    func simctlFailureSurfaces() async {
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
        let simMock = MockXcodeProcessRunner()
        simMock.defaultRunOutcome = .failure(.spawnFailed("xcrun missing"))
        let session = XcodeRunSession(
            xcodebuildRunner: xcodebuild,
            simulatorCatalog: SimulatorCatalog(
                runner: simMock,
                toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }
            ),
            appLauncher: RecordingAppLauncher()
        )
        let inputs = XcodeRunInputs(
            project: XcodeProjectRef(
                url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
                kind: .project
            ),
            scheme: "Demo",
            destinationArg: "id=AAAA-UDID",
            isSimulatorDestination: true,
            simulatorUDID: "AAAA-UDID"
        )
        let outcome = await session.run(inputs: inputs) { _ in }
        if case .launchFailed = outcome {
            // expected
        } else {
            Issue.record("expected .launchFailed, got \(outcome)")
        }
    }
}
