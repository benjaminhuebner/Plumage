import Foundation
// LanguageSupport 0.15.4 (CodeEditorView) hasn't adopted Swift 6 strict
// concurrency — its `LanguageConfiguration.Token` enum isn't Sendable. We
// wrap it in `DiffToken` here and need `@preconcurrency` to allow the
// non-Sendable kind to live inside our Sendable wrapper.
@preconcurrency import LanguageSupport

nonisolated public struct Hunk: Sendable, Equatable, Hashable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let headerContext: String
    public let lines: [Line]

    public init(
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        headerContext: String = "",
        lines: [Line] = []
    ) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.headerContext = headerContext
        self.lines = lines
    }
}

nonisolated public enum LineKind: Sendable, Equatable, Hashable {
    case context
    case added
    case removed
}

nonisolated public struct Line: Sendable, Equatable, Hashable {
    public let kind: LineKind
    public let content: String
    public let tokens: [DiffToken]
    public let hasNoTrailingNewline: Bool

    public init(
        kind: LineKind,
        content: String,
        tokens: [DiffToken] = [],
        hasNoTrailingNewline: Bool = false
    ) {
        self.kind = kind
        self.content = content
        self.tokens = tokens
        self.hasNoTrailingNewline = hasNoTrailingNewline
    }
}

// Wrapper around LanguageSupport's tokeniser output. The library's
// `Tokeniser.Token` and `LanguageConfiguration.Token` only conform to
// `Equatable`; we need Sendable + Hashable on every output type of this
// module (cache-key precondition, decisions.md 2026-05-25 #00040 will
// document). `kind` carries the upstream enum verbatim so consumers can
// pattern-match on it; `range` matches the NSRange-convention CodeEditorView
// uses throughout (notes.md 2026-05-13 #00008).
nonisolated public struct DiffToken: Sendable, Equatable, Hashable {
    public let kind: LanguageConfiguration.Token
    public let range: NSRange

    public init(kind: LanguageConfiguration.Token, range: NSRange) {
        self.kind = kind
        self.range = range
    }

    public static func == (lhs: DiffToken, rhs: DiffToken) -> Bool {
        lhs.kind == rhs.kind && lhs.range == rhs.range
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        // LanguageConfiguration.Token is Equatable but not Hashable; the
        // mirror description is deterministic for a given case + payload.
        hasher.combine(String(describing: kind))
    }
}
