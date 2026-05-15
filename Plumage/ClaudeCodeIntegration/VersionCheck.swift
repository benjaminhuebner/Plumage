import Foundation

nonisolated struct VersionCheck: Sendable, Equatable {
    let version: SemanticVersion
    let binaryURL: URL
    let inSupportedRange: Bool
}

nonisolated struct SpawnResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

nonisolated struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }

    static func parse(_ raw: String) -> SemanticVersion? {
        // Match the first `\d+\.\d+\.\d+` sequence anywhere in raw.
        // Handles both `1.2.3 (Claude Code)` and `@anthropic-ai/claude-code/1.2.3 darwin-arm64`.
        guard let regex = try? Regex(#"(\d+)\.(\d+)\.(\d+)"#) else { return nil }
        guard let match = raw.firstMatch(of: regex) else { return nil }
        guard match.output.count == 4 else { return nil }
        guard
            let majorSub = match.output[1].substring,
            let minorSub = match.output[2].substring,
            let patchSub = match.output[3].substring,
            let major = Int(majorSub),
            let minor = Int(minorSub),
            let patch = Int(patchSub)
        else { return nil }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

nonisolated enum ProcessRunnerError: Error, Sendable, Equatable {
    case binaryNotFound
    case parseError(String)
    case spawnFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
}
