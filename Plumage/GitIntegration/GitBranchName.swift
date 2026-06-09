import Foundation

// Conservative subset of git's check-ref-format rules. The security-relevant
// part is rejecting a leading "-": branch names from config.json and spec
// frontmatter flow as positional arguments into git subprocess calls
// (checkout, merge-base, branch -d, init -b, diff ranges), where a crafted
// value like "--output=/tmp/x" would be parsed as an option.
nonisolated enum GitBranchName {
    static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 250 else { return false }
        if name.hasPrefix("-") || name.hasPrefix("/") || name.hasPrefix(".") { return false }
        if name.hasSuffix("/") || name.hasSuffix(".") || name.hasSuffix(".lock") { return false }
        if name.contains("..") || name.contains("//") || name.contains("@{") { return false }
        for scalar in name.unicodeScalars {
            if scalar.value <= 0x20 || scalar.value == 0x7F { return false }
            if forbidden.contains(scalar) { return false }
        }
        return true
    }

    private static let forbidden = Set<Unicode.Scalar>(["~", "^", ":", "?", "*", "[", "\\"])
}
