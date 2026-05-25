import Foundation

nonisolated enum ToolchainLocator {
    // /usr/bin/xcodebuild and /usr/bin/xcrun are shims provided by macOS and
    // always sit in the system default PATH (unlike the `claude` CLI — see
    // notes.md 2026-05-15). They resolve to the active Xcode via xcode-select.
    static let knownXcodebuildPaths: [String] = [
        "/usr/bin/xcodebuild",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
    ]

    static let knownXcrunPaths: [String] = [
        "/usr/bin/xcrun",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/xcrun",
    ]

    // /usr/bin/git is the macOS shim that resolves to the active Xcode CLI
    // tools git. /opt/homebrew/bin/git is the Apple-Silicon Homebrew default,
    // /usr/local/bin/git the Intel default.
    static let knownGitPaths: [String] = [
        "/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ]

    static func xcodebuild(fileManager: FileManager = .default) -> URL? {
        locate(filename: "xcodebuild", knownPaths: knownXcodebuildPaths, fileManager: fileManager)
    }

    static func xcrun(fileManager: FileManager = .default) -> URL? {
        locate(filename: "xcrun", knownPaths: knownXcrunPaths, fileManager: fileManager)
    }

    static func git(fileManager: FileManager = .default) -> URL? {
        locate(filename: "git", knownPaths: knownGitPaths, fileManager: fileManager)
    }

    static func locate(
        filename: String,
        knownPaths: [String],
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        for path in knownPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let viaPath = scanPATH(filename: filename, fileManager: fileManager, environment: environment) {
            return viaPath
        }
        return nil
    }

    static func scanPATH(
        filename: String,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let pathEnv = environment["PATH"], !pathEnv.isEmpty else { return nil }
        for entry in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(filename)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static let installXcodeURLString = "macappstore://apps.apple.com/app/xcode/id497799835"

    static var installXcodeURL: URL? {
        URL(string: installXcodeURLString)
    }
}
