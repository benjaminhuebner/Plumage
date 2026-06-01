import Foundation

// Best-effort inference of a project's `ProjectKind` from the files already on
// disk. Pure over the passed URL — no global paths, no subprocess. Returns nil
// only when `url` is not a readable directory; an unrecognized directory is
// `.other`.
nonisolated enum ProjectKindDetector {
    static func detect(in url: URL) -> ProjectKind? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        if let xcode = XcodeProjectDiscovery.find(in: url) {
            return applePlatform(from: xcode)
        }

        let packageSwift = url.appending(path: "Package.swift")
        if fm.fileExists(atPath: packageSwift.path) {
            return swiftPackageKind(at: packageSwift)
        }

        return .other
    }

    // A workspace can't be introspected cheaply, so it falls back to the safe
    // multiplatform default. For a project we scan the pbxproj's platform
    // strings: both iOS and macOS present means multiplatform.
    private static func applePlatform(from ref: XcodeProjectRef) -> ProjectKind {
        guard ref.kind == .project else { return .appleMultiplatform }
        let pbxproj = ref.url.appending(path: "project.pbxproj")
        guard let contents = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .appleMultiplatform
        }
        let lower = contents.lowercased()
        let hasIOS = lower.contains("iphoneos")
        let hasMac = lower.contains("macosx")
        switch (hasIOS, hasMac) {
        case (true, true): return .appleMultiplatform
        case (true, false): return .iOS
        case (false, true): return .macOS
        case (false, false): return .appleMultiplatform
        }
    }

    private static func swiftPackageKind(at packageSwift: URL) -> ProjectKind {
        guard let contents = try? String(contentsOf: packageSwift, encoding: .utf8) else {
            return .swiftCLI
        }
        let lower = contents.lowercased()
        if lower.contains("vapor") { return .vapor }
        if lower.contains("hummingbird") { return .hummingbird }
        return .swiftCLI
    }
}
