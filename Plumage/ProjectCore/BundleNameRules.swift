import Foundation

// A bundle folder name must be a single, non-empty path component — shared by
// rename, migrate, and new-project validation so the rule can't drift.
nonisolated enum BundleNameRules {
    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
    }
}
