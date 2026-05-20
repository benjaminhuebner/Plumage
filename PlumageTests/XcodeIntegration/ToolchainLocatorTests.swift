import Foundation
import Testing

@testable import Plumage

@Suite("ToolchainLocator")
struct ToolchainLocatorTests {
    @Test("returns the canonical /usr/bin/xcodebuild on this host")
    func xcodebuildResolvable() throws {
        let url = try #require(ToolchainLocator.xcodebuild())
        #expect(url.path == "/usr/bin/xcodebuild")
    }

    @Test("returns the canonical /usr/bin/xcrun on this host")
    func xcrunResolvable() throws {
        let url = try #require(ToolchainLocator.xcrun())
        #expect(url.path == "/usr/bin/xcrun")
    }

    @Test("locate falls back to a PATH entry when known-paths miss")
    func locateWalksPATH() {
        let url = ToolchainLocator.locate(
            filename: "ls",
            knownPaths: [],
            environment: ["PATH": "/nonexistent:/usr/bin:/bin"]
        )
        #expect(url?.path == "/bin/ls")
    }

    @Test("locate returns nil when neither known-paths nor PATH hit")
    func locateReturnsNilWhenMissing() {
        let url = ToolchainLocator.locate(
            filename: "this-binary-does-not-exist-\(UUID().uuidString)",
            knownPaths: [],
            environment: ["PATH": "/usr/bin:/bin"]
        )
        #expect(url == nil)
    }

    @Test("locate returns nil when PATH is empty")
    func locateNilWithEmptyPATH() {
        let url = ToolchainLocator.locate(
            filename: "xcodebuild",
            knownPaths: [],
            environment: ["PATH": ""]
        )
        #expect(url == nil)
    }

    @Test("install-Xcode URL is well-formed")
    func installURLValid() {
        let url = ToolchainLocator.installXcodeURL
        #expect(url != nil)
        #expect(url?.scheme == "macappstore")
    }

    @Test("locate prefers known paths over PATH")
    func locatePrefersKnownPaths() {
        let url = ToolchainLocator.locate(
            filename: "ls",
            knownPaths: ["/bin/ls"],
            environment: ["PATH": "/usr/bin"]
        )
        #expect(url?.path == "/bin/ls")
    }
}
