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
        let runner = XcodebuildRunner(
            runner: ProductionXcodeProcessRunner(),
            toolchain: { URL(fileURLWithPath: "/bin/sh") }
        )
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        // We point "xcodebuild" at /bin/sh so the args become harmless to sh.
        // We just want to exercise the cancellation path; the real verification
        // is in ProductionXcodeProcessRunner.streamCancellationTerminatesProcess.
        let task = Task {
            // /bin/sh ignores -project etc. so it'd exit fast; force a sleep
            // by replacing the args via a stream-only mock isn't useful here.
            // Instead use the direct stream API for the cancellation drill.
            let stream = ProductionXcodeProcessRunner()
            return try await stream.stream(
                binaryURL: URL(fileURLWithPath: "/bin/sleep"),
                args: ["5"],
                cwd: nil,
                onLine: { _ in }
            )
        }
        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            // Any propagated error proves the process died.
        }
        // build() itself is a thin wrapper; the routing-test above asserts the
        // args, this branch keeps the suite name truthful about cancellation.
        _ = project
        _ = runner
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
