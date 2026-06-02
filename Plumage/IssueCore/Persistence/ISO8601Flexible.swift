import Foundation

// Shared, allocation-per-call ISO-8601 parsing/formatting.
//
// ISO8601DateFormatter is NOT documented by Apple as thread-safe — the
// reentrancy guarantee covers DateFormatter, not this subclass. After repeated
// cached-formatter rollbacks (notes.md 2026-05-13 / 2026-05-14) the project
// standardized on per-call construction: the allocation is negligible against
// the surrounding YAML/JSON decode, and it sidesteps the data race a shared
// `nonisolated(unsafe)` instance would expose under concurrent Task.detached
// parses. One home for the primary/fallback pair that was duplicated across
// SpecParser, FrontmatterMutator, NextIssueAllocator and the ClaudeAccount
// JSON decoders.
nonisolated enum ISO8601Flexible {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}
