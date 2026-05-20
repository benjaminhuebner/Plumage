import Foundation
import Testing

@testable import Plumage

@Suite("XcodebuildRunner.build")
struct XcodebuildRunnerBuildTests {
    @Test("build forwards scheme + destination + configuration to xcodebuild")
    func buildArgsRouting() async throws {
        let mock = MockXcodeProcessRunner()
        mock.streamOutcome = .success(lines: ["compile started"], exitCode: 0)
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )
        let collected = LineCollector()
        let exit = try await runner.build(
            project: project,
            scheme: "Plumage",
            destinationArg: "platform=macOS"
        ) { line in collected.append(line) }
        #expect(exit == 0)
        #expect(collected.lines == ["compile started"])
        let invocation = try #require(mock.invocations.first)
        #expect(
            invocation.args == [
                "-project", "/tmp/Demo/Demo.xcodeproj",
                "-scheme", "Plumage",
                "-destination", "platform=macOS",
                "-configuration", "Debug",
                "build",
            ])
    }

    @Test("build can be cancelled mid-stream (real /bin/sh subprocess)")
    func buildCancellation() async {
        // build() is a thin wrapper around runner.stream(). The
        // cancellation path is fully verified in
        // ProductionXcodeProcessRunnerTests.streamCancellationTerminatesProcess
        // — we keep this drill light, exercising the same stream() path with
        // a deterministic wait-on-marker rather than wallclock sleep.
        let (signal, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await ProductionXcodeProcessRunner().stream(
                binaryURL: URL(fileURLWithPath: "/bin/sh"),
                args: ["-c", "echo started; sleep 5"],
                cwd: nil,
                onLine: { line in
                    if line == "started" { continuation.yield() }
                }
            )
        }
        var iterator = signal.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            // Any propagated error proves the process died.
        }
    }

    @Test("build propagates a non-zero exit through stream's return value")
    func buildPropagatesExitCode() async throws {
        let mock = MockXcodeProcessRunner()
        mock.streamOutcome = .success(lines: ["error"], exitCode: 65)
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )
        let collected = LineCollector()
        let exit = try await runner.build(
            project: project,
            scheme: "X",
            destinationArg: "platform=macOS"
        ) { line in collected.append(line) }
        #expect(exit == 65)
        #expect(collected.lines == ["error"])
    }

    @Test("build throws toolchainNotFound when locator returns nil")
    func buildMissingToolchain() async {
        let mock = MockXcodeProcessRunner()
        let runner = XcodebuildRunner(runner: mock, toolchain: { nil })
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        do {
            _ = try await runner.build(
                project: project,
                scheme: "X",
                destinationArg: "platform=macOS"
            ) { _ in }
            Issue.record("expected toolchainNotFound")
        } catch let error as XcodeProcessRunnerError {
            #expect(error == .toolchainNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("parseBuildSettings extracts KEY = VALUE pairs")
    func parsesBuildSettings() {
        let raw = """
            Build settings from command line:
                BUILT_PRODUCTS_DIR = /tmp/Build/Products/Debug
                FULL_PRODUCT_NAME = Demo.app
                PRODUCT_BUNDLE_IDENTIFIER = com.example.demo
                IGNORED = ignored
            """
        let settings = XcodebuildRunner.parseBuildSettings(raw)
        #expect(settings["BUILT_PRODUCTS_DIR"] == "/tmp/Build/Products/Debug")
        #expect(settings["FULL_PRODUCT_NAME"] == "Demo.app")
        #expect(settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.demo")
    }

    @Test("parseSchemeCompatibility recognises macOS-only schemes")
    func parsesMacOnly() {
        let raw = """
            \tAvailable destinations for the "Plumage" scheme:
            \t\t{ platform:macOS, arch:arm64, id:abc, name:My Mac }
            \t\t{ platform:macOS, name:Any Mac }
            """
        let compat = XcodebuildRunner.parseSchemeCompatibility(raw)
        #expect(compat.supportsMac == true)
        #expect(compat.supportsIOSSimulator == false)
    }

    @Test("parseSchemeCompatibility recognises iOS apps")
    func parsesIOS() {
        let raw = """
            \tAvailable destinations for the "DemoApp" scheme:
            \t\t{ platform:iOS, id:..., name:Any iOS Device }
            \t\t{ platform:iOS Simulator, id:..., OS:26.5, name:iPhone 17 Pro }
            \t\t{ platform:iOS Simulator, id:..., OS:26.5, name:iPad Pro 13 }
            """
        let compat = XcodebuildRunner.parseSchemeCompatibility(raw)
        #expect(compat.supportsMac == false)
        #expect(compat.supportsIOSSimulator == true)
    }

    @Test("parseSchemeCompatibility recognises Catalyst (mac + iOS)")
    func parsesMacAndIOS() {
        let raw = """
            \t\t{ platform:macOS, arch:arm64, variant:Mac Catalyst, name:My Mac }
            \t\t{ platform:iOS Simulator, id:..., name:iPhone 17 Pro }
            """
        let compat = XcodebuildRunner.parseSchemeCompatibility(raw)
        #expect(compat.supportsMac == true)
        #expect(compat.supportsIOSSimulator == true)
    }

    @Test("parseSchemeCompatibility falls back to .unknown on empty output")
    func failsOpenOnEmpty() {
        let compat = XcodebuildRunner.parseSchemeCompatibility("")
        #expect(compat == .unknown)
    }

    @Test("parseSchemeCompatibility falls back to .unknown when no platform: row")
    func failsOpenWithoutPlatform() {
        let compat = XcodebuildRunner.parseSchemeCompatibility(
            """
            {
              "project": {
                "schemes": ["Plumage"]
              }
            }
            """
        )
        #expect(compat == .unknown)
    }

    @Test("appBundleURL composes from build settings")
    func appBundleURLComposes() {
        let url = XcodebuildRunner.appBundleURL(from: [
            "BUILT_PRODUCTS_DIR": "/tmp/Build",
            "FULL_PRODUCT_NAME": "Demo.app",
        ])
        #expect(url?.path == "/tmp/Build/Demo.app")
    }
}
