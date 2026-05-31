import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKindDetector")
struct ProjectKindDetectorTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "KindDetect-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeXcodeProject(in dir: URL, name: String, pbxproj: String) throws {
        let proj = dir.appending(path: "\(name).xcodeproj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try pbxproj.write(to: proj.appending(path: "project.pbxproj"), atomically: true, encoding: .utf8)
    }

    private func writePackage(in dir: URL, contents: String) throws {
        try contents.write(to: dir.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
    }

    @Test("Nonexistent directory returns nil")
    func nonexistentReturnsNil() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        #expect(ProjectKindDetector.detect(in: dir) == nil)
    }

    @Test("Empty directory is .other")
    func emptyIsOther() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ProjectKindDetector.detect(in: dir) == .other)
    }

    @Test("Xcode project with iphoneos SDK is iOS")
    func xcodeIOS() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeXcodeProject(in: dir, name: "App", pbxproj: "SDKROOT = iphoneos;")
        #expect(ProjectKindDetector.detect(in: dir) == .iOS)
    }

    @Test("Xcode project with macosx SDK is macOS")
    func xcodeMacOS() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeXcodeProject(in: dir, name: "App", pbxproj: "SDKROOT = macosx;")
        #expect(ProjectKindDetector.detect(in: dir) == .macOS)
    }

    @Test("Xcode project supporting both platforms is multiplatform")
    func xcodeMultiplatform() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeXcodeProject(
            in: dir, name: "App",
            pbxproj: "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\";")
        #expect(ProjectKindDetector.detect(in: dir) == .appleMultiplatform)
    }

    @Test("Xcode workspace falls back to multiplatform")
    func xcodeWorkspace() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = dir.appending(path: "App.xcworkspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        #expect(ProjectKindDetector.detect(in: dir) == .appleMultiplatform)
    }

    @Test("Package.swift with Vapor dependency is vapor")
    func packageVapor() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writePackage(
            in: dir,
            contents: ".package(url: \"https://github.com/vapor/vapor.git\", from: \"4.0.0\")")
        #expect(ProjectKindDetector.detect(in: dir) == .vapor)
    }

    @Test("Package.swift with Hummingbird dependency is hummingbird")
    func packageHummingbird() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writePackage(
            in: dir,
            contents: ".package(url: \"https://github.com/hummingbird-project/hummingbird.git\", from: \"2.0.0\")")
        #expect(ProjectKindDetector.detect(in: dir) == .hummingbird)
    }

    @Test("Package.swift with an executable target is swiftCLI")
    func packageExecutable() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writePackage(in: dir, contents: ".executableTarget(name: \"tool\")")
        #expect(ProjectKindDetector.detect(in: dir) == .swiftCLI)
    }

    @Test("Plain library Package.swift falls back to swiftCLI")
    func packageLibrary() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writePackage(in: dir, contents: ".library(name: \"Lib\", targets: [\"Lib\"])")
        #expect(ProjectKindDetector.detect(in: dir) == .swiftCLI)
    }
}
