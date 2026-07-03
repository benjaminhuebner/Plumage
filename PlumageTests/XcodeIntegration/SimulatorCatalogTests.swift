import Foundation
import Testing

@testable import Plumage

@Suite("SimulatorCatalog")
struct SimulatorCatalogTests {
    @Test("parses simctl JSON and skips unavailable devices")
    func parsesFixture() throws {
        let data = try loadFixture("simctl-devices.json")
        let sims = try SimulatorCatalog.parseDevices(data: data)
        // iOS-26-5 has 2 available, iOS-26-4 has 1 available (one isAvailable=false),
        // watchOS-26-2 has 1 available. tvOS bucket is empty. Total = 4.
        #expect(sims.count == 4)
        let names = sims.map(\.name).sorted()
        #expect(names == ["Apple Watch Series 10", "iPad Pro 13", "iPhone 16", "iPhone 17 Pro"])
    }

    @Test("parses runtime identifiers into platform + version")
    func parsesRuntime() {
        let runtime = SimulatorCatalog.parseRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        #expect(runtime.platform == .iOS)
        #expect(runtime.version == SemVersion(major: 26, minor: 5))
        #expect(runtime.displayName == "iOS 26.5")
    }

    @Test("falls back to .other for unknown platform")
    func unknownPlatform() {
        let runtime = SimulatorCatalog.parseRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.fakeOS-1-2")
        #expect(runtime.platform == .other)
    }

    @Test("groupedByRuntime sorts iOS versions descending, names ascending inside")
    func groupedByRuntime() throws {
        let data = try loadFixture("simctl-devices.json")
        let sims = try SimulatorCatalog.parseDevices(data: data)
        let iosSims = sims.filter { $0.runtime.platform == .iOS }
        let groups = SimulatorCatalog.groupedByRuntime(iosSims)
        #expect(groups.count == 2)
        #expect(groups.first?.runtime.displayName == "iOS 26.5")
        #expect(groups.last?.runtime.displayName == "iOS 26.4")
        let firstNames = groups.first?.simulators.map(\.name) ?? []
        #expect(firstNames == ["iPad Pro 13", "iPhone 17 Pro"])
    }

    @Test("Booted state survives parsing")
    func bootedStatePreserved() throws {
        let data = try loadFixture("simctl-devices.json")
        let sims = try SimulatorCatalog.parseDevices(data: data)
        let booted = try #require(sims.first { $0.state == .booted })
        #expect(booted.name == "iPad Pro 13")
    }

    @Test("listDevices passes the expected args to xcrun")
    func listDevicesArgs() async throws {
        let mock = MockXcodeProcessRunner()
        let data = try loadFixture("simctl-devices.json")
        mock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: data, stderr: Data()))
        let catalog = SimulatorCatalog(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcrun") }
        )

        _ = try await catalog.listDevices()
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.args == ["simctl", "list", "devices", "--json"])
    }

    @Test("boot translates simctl `already booted` into success")
    func bootIdempotent() async throws {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcrun")
        mock.setRunOutcome(
            .success(
                XcodeSpawnResult(
                    exitCode: 149,
                    stdout: Data(),
                    stderr: Data("Unable to boot device in current state: Booted".utf8)
                )),
            forBinary: url
        )
        let catalog = SimulatorCatalog(runner: mock, toolchain: { url })
        try await catalog.boot(udid: "DEAD-BEEF")
    }

    @Test("boot surfaces real non-zero exits")
    func bootRaisesRealErrors() async {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcrun")
        mock.setRunOutcome(
            .success(
                XcodeSpawnResult(
                    exitCode: 1,
                    stdout: Data(),
                    stderr: Data("device not found".utf8)
                )),
            forBinary: url
        )
        let catalog = SimulatorCatalog(runner: mock, toolchain: { url })
        do {
            try await catalog.boot(udid: "DEAD-BEEF")
            Issue.record("expected nonZeroExit")
        } catch let error as XcodeProcessRunnerError {
            if case .nonZeroExit = error {
                // expected
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("install passes the .app path through")
    func installArgs() async throws {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcrun")
        let catalog = SimulatorCatalog(runner: mock, toolchain: { url })
        try await catalog.install(udid: "U-1", appURL: URL(fileURLWithPath: "/tmp/App.app"))
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.args == ["simctl", "install", "U-1", "/tmp/App.app"])
    }

    @Test("launch forwards bundleID")
    func launchArgs() async throws {
        let mock = MockXcodeProcessRunner()
        let url = URL(fileURLWithPath: "/usr/bin/xcrun")
        let catalog = SimulatorCatalog(runner: mock, toolchain: { url })
        try await catalog.launch(udid: "U-1", bundleID: "com.example.app")
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.args == ["simctl", "launch", "U-1", "com.example.app"])
    }

    @Test("missing toolchain bubbles up consistently")
    func missingToolchain() async {
        let mock = MockXcodeProcessRunner()
        let catalog = SimulatorCatalog(runner: mock, toolchain: { nil })
        do {
            _ = try await catalog.listDevices()
            Issue.record("expected toolchainNotFound")
        } catch let error as XcodeProcessRunnerError {
            #expect(error == .toolchainNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: name)
        return try Data(contentsOf: url)
    }
}
