import Foundation

nonisolated enum SupportedClaudeVersion {
    static let supportedMajors: ClosedRange<Int> = 1...2

    static func inSupportedRange(_ version: SemanticVersion) -> Bool {
        supportedMajors.contains(version.major)
    }

    static var supportedRangeDescription: String {
        let lower = supportedMajors.lowerBound
        let upper = supportedMajors.upperBound
        return lower == upper ? "\(lower).x" : "\(lower).x – \(upper).x"
    }

    static let installCommand: String = "npm install -g @anthropic-ai/claude-code"

    // GUI apps launched via LaunchServices do not source the user's interactive
    // shell rc files, so `claude` installs in dotfile-managed bin directories
    // are invisible to a bare `which` lookup. We probe the four locations the
    // current and prior installers actually use; broader resolution would
    // require spawning a login shell, which is slow and hangs on broken rc.
    static let knownInstallPaths: [String] = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    static var knownInstallURLs: [URL] {
        knownInstallPaths.map { displayPath in
            URL(fileURLWithPath: (displayPath as NSString).expandingTildeInPath)
        }
    }

    static var searchPathDescription: String {
        "PATH and: " + knownInstallPaths.joined(separator: ", ")
    }
}
