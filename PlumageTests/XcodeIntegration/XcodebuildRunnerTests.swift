import Foundation
import Testing

@testable import Plumage

@Suite("XcodebuildRunner")
struct XcodebuildRunnerTests {
    @Test("parses a project-rooted -list -json fixture")
    func parsesProjectFixture() throws {
        let data = try loadFixture("list-project.json")
        let listing = try XcodebuildRunner.parseListing(data: data)
        #expect(listing.projectName == "Plumage")
        #expect(listing.schemes == ["Plumage", "PlumageTests"])
    }

    @Test("parses a workspace-rooted -list -json fixture")
    func parsesWorkspaceFixture() throws {
        let data = try loadFixture("list-workspace.json")
        let listing = try XcodebuildRunner.parseListing(data: data)
        #expect(listing.projectName == "Demo")
        #expect(listing.schemes == ["App", "Tests", "WatchApp"])
    }

    @Test("throws parseError on a missing root key")
    func parseErrorOnEmptyEnvelope() {
        let data = Data("{}".utf8)
        do {
            _ = try XcodebuildRunner.parseListing(data: data)
            Issue.record("expected parseError")
        } catch let error as XcodeProcessRunnerError {
            if case .parseError = error {
                // expected
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("throws parseError on invalid JSON")
    func parseErrorOnInvalidJSON() {
        let data = Data("not json".utf8)
        do {
            _ = try XcodebuildRunner.parseListing(data: data)
            Issue.record("expected parseError")
        } catch let error as XcodeProcessRunnerError {
            if case .parseError = error {
                // expected
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("listSchemes routes args to the mocked runner")
    func listSchemesRoutesArgs() async throws {
        let mock = MockXcodeProcessRunner()
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        let data = try loadFixture("list-project.json")
        mock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: data, stderr: Data()))
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )

        let listing = try await runner.listSchemes(at: project)
        #expect(listing.schemes.contains("Plumage"))
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.args == ["-project", "/tmp/Demo/Demo.xcodeproj", "-list", "-json"])
    }

    @Test("listSchemes uses -workspace flag for a workspace ref")
    func listSchemesWorkspaceFlag() async throws {
        let mock = MockXcodeProcessRunner()
        let workspace = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcworkspace"),
            kind: .workspace
        )
        let data = try loadFixture("list-workspace.json")
        mock.defaultRunOutcome = .success(
            XcodeSpawnResult(exitCode: 0, stdout: data, stderr: Data()))
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )

        _ = try await runner.listSchemes(at: workspace)
        let invocation = try #require(mock.invocations.first)
        #expect(invocation.args.first == "-workspace")
    }

    @Test("listSchemes throws toolchainNotFound when xcodebuild is missing")
    func listSchemesPropagatesMissingToolchain() async {
        let mock = MockXcodeProcessRunner()
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { nil }
        )
        do {
            _ = try await runner.listSchemes(at: project)
            Issue.record("expected toolchainNotFound")
        } catch let error as XcodeProcessRunnerError {
            #expect(error == .toolchainNotFound)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("listSchemes propagates non-zero exit as nonZeroExit")
    func listSchemesNonZeroExit() async {
        let mock = MockXcodeProcessRunner()
        let project = XcodeProjectRef(
            url: URL(fileURLWithPath: "/tmp/Demo/Demo.xcodeproj"),
            kind: .project
        )
        mock.defaultRunOutcome = .success(
            XcodeSpawnResult(
                exitCode: 65,
                stdout: Data(),
                stderr: Data("xcodebuild: error".utf8)
            ))
        let runner = XcodebuildRunner(
            runner: mock,
            toolchain: { URL(fileURLWithPath: "/usr/bin/xcodebuild") }
        )

        do {
            _ = try await runner.listSchemes(at: project)
            Issue.record("expected nonZeroExit")
        } catch let error as XcodeProcessRunnerError {
            if case .nonZeroExit(let code, _) = error {
                #expect(code == 65)
            } else {
                Issue.record("wrong error: \(error)")
            }
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
