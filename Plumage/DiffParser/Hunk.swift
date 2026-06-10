import Foundation
// LanguageSupport 0.15.4 (CodeEditorView) hasn't adopted Swift 6 strict
// concurrency — its `LanguageConfiguration.Token` enum isn't Sendable. The
// enum's payload is itself a value-type (`Flavour`), so wrapping it in our
// Sendable `DiffToken` is runtime-safe; we need `@preconcurrency` only to
// silence the compile-time check.
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

// `range` is a `Range<String.Index>` into the enclosing `Line.content`. Slicing
// works directly via `content[token.range]`. The indices are only meaningful
// with the exact `content` string that produced them — different strings have
// different `String.Index` spaces.
nonisolated public struct DiffToken: Sendable, Equatable, Hashable {
    public let kind: LanguageConfiguration.Token
    public let range: Range<String.Index>

    public init(kind: LanguageConfiguration.Token, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }

    public static func == (lhs: DiffToken, rhs: DiffToken) -> Bool {
        lhs.kind == rhs.kind && lhs.range == rhs.range
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        Self.hash(kind: kind, into: &hasher)
    }

    // Explicit per-case discriminator. Upstream `LanguageConfiguration.Token`
    // is Equatable but not Hashable, so we cannot synthesise. A new upstream
    // case shows up as a non-exhaustive switch warning here — preferable to
    // silent Mirror drift.
    private static func hash(kind: LanguageConfiguration.Token, into hasher: inout Hasher) {
        switch kind {
        case .roundBracketOpen: hasher.combine(0)
        case .roundBracketClose: hasher.combine(1)
        case .squareBracketOpen: hasher.combine(2)
        case .squareBracketClose: hasher.combine(3)
        case .curlyBracketOpen: hasher.combine(4)
        case .curlyBracketClose: hasher.combine(5)
        case .string: hasher.combine(6)
        case .character: hasher.combine(7)
        case .number: hasher.combine(8)
        case .singleLineComment: hasher.combine(9)
        case .nestedCommentOpen: hasher.combine(10)
        case .nestedCommentClose: hasher.combine(11)
        case .identifier(let flavour):
            hasher.combine(12)
            hash(flavour: flavour, into: &hasher)
        case .operator(let flavour):
            hasher.combine(13)
            hash(flavour: flavour, into: &hasher)
        case .keyword: hasher.combine(14)
        case .symbol: hasher.combine(15)
        case .regexp: hasher.combine(16)
        }
    }

    private static func hash(flavour: LanguageConfiguration.Flavour?, into hasher: inout Hasher) {
        guard let flavour else {
            hasher.combine(0)
            return
        }
        hasher.combine(1)
        switch flavour {
        case .module: hasher.combine(0)
        case .type(let typeFlavour):
            hasher.combine(1)
            hash(typeFlavour: typeFlavour, into: &hasher)
        case .parameter: hasher.combine(2)
        case .typeParameter: hasher.combine(3)
        case .variable: hasher.combine(4)
        case .property: hasher.combine(5)
        case .enumCase: hasher.combine(6)
        case .function: hasher.combine(7)
        case .method: hasher.combine(8)
        case .macro: hasher.combine(9)
        case .modifier: hasher.combine(10)
        }
    }

    private static func hash(typeFlavour: LanguageConfiguration.TypeFlavour, into hasher: inout Hasher) {
        switch typeFlavour {
        case .class: hasher.combine(0)
        case .struct: hasher.combine(1)
        case .enum: hasher.combine(2)
        case .protocol: hasher.combine(3)
        case .other: hasher.combine(4)
        }
    }
}
