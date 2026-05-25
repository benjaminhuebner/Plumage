import Foundation
import LanguageSupport

nonisolated public enum DiffParser {
    public static func parse(unifiedDiff: String) -> [FileDiff] {
        var input = unifiedDiff
        if input.hasPrefix("\u{FEFF}") { input.removeFirst() }
        input = input.replacingOccurrences(of: "\r\n", with: "\n")
        // Strip trailing newlines so the EOF marker doesn't surface as a
        // phantom blank body line inside the last hunk. Real blank context
        // lines mid-hunk survive (they sit between other lines).
        while input.hasSuffix("\n") { input.removeLast() }
        if input.isEmpty { return [] }

        var files: [FileDiff] = []
        var state = ParseState()

        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            consume(line: String(line), state: &state, files: &files)
        }
        flushFile(state: &state, files: &files)
        return files
    }

    private struct ParseState {
        var currentFile: PartialFileDiff?
        var currentHunk: PartialHunk?
        var lastBodyLineIndex: Int?
        var sawMalformedHunk = false
    }

    private struct PartialFileDiff {
        var path: String
        var status: FileStatus = .modified
        var pendingOldMode: String?
        var pendingNewMode: String?
        var fileMode: String?
        var hunks: [Hunk] = []
        var tokeniser: LanguageConfiguration.Tokeniser?
    }

    private struct PartialHunk {
        var oldStart: Int
        var oldCount: Int
        var newStart: Int
        var newCount: Int
        var headerContext: String
        var lines: [Line] = []
    }

    // MARK: - Line dispatch

    private static func consume(
        line: String,
        state: inout ParseState,
        files: inout [FileDiff]
    ) {
        if line.hasPrefix("diff --git ") {
            flushFile(state: &state, files: &files)
            startFile(headerLine: line, state: &state)
            return
        }

        guard state.currentFile != nil else { return }

        // An empty line inside a hunk represents a blank context line that some
        // upstream tools emit without the leading space — treat as context.
        if state.currentHunk != nil, line.isEmpty {
            appendContextLine(content: "", state: &state)
            return
        }

        if state.currentHunk != nil, isBodyLine(line) {
            appendBodyLine(line, state: &state)
            return
        }

        if line.hasPrefix("@@") {
            flushHunk(state: &state)
            startHunk(headerLine: line, state: &state)
            return
        }

        handleHeaderLine(line, state: &state)
    }

    private static func isBodyLine(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first == " " || first == "+" || first == "-" || first == "\\"
    }

    // MARK: - File start

    private static func startFile(headerLine: String, state: inout ParseState) {
        let path = extractPath(fromDiffGitHeader: headerLine)
        state.currentFile = PartialFileDiff(
            path: path,
            tokeniser: LanguageDetector.tokeniser(forPath: path)
        )
        state.sawMalformedHunk = false
    }

    // Handles three header shapes:
    //   diff --git a/foo b/foo                  → unquoted, identical paths
    //   diff --git "a/foo bar" "b/foo bar"      → C-quoted (path has special chars)
    //   diff --git foo bar                      → --no-prefix (rare)
    // Splits on the first occurrence of ` b/` (or `" "b/` for quoted), so paths
    // containing spaces survive. C-style escape decoding inside quoted paths is
    // not implemented — callers see the raw quoted string for display.
    private static func extractPath(fromDiffGitHeader header: String) -> String {
        let body = header.dropFirst("diff --git ".count)
        if body.hasPrefix("\"a/") {
            if let separator = body.range(of: "\" \"b/") {
                let tail = body[separator.upperBound...]
                // Drop the trailing closing quote, if present.
                if tail.hasSuffix("\"") { return String(tail.dropLast()) }
                return String(tail)
            }
            return ""
        }
        if body.hasPrefix("a/") {
            if let separator = body.range(of: " b/") {
                return String(body[separator.upperBound...])
            }
            return ""
        }
        // --no-prefix or malformed: best-effort split on first space.
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return "" }
        return String(parts[1])
    }

    // MARK: - Header (non-body, non-hunk)

    private static func handleHeaderLine(_ line: String, state: inout ParseState) {
        if line.hasPrefix("new file mode ") {
            let mode = String(line.dropFirst("new file mode ".count))
            state.currentFile?.status = .added
            state.currentFile?.fileMode = mode
            return
        }
        if line.hasPrefix("deleted file mode ") {
            let mode = String(line.dropFirst("deleted file mode ".count))
            state.currentFile?.status = .deleted
            state.currentFile?.fileMode = mode
            return
        }
        if line.hasPrefix("index ") {
            handleIndexLine(line, state: &state)
            return
        }
        if line.hasPrefix("old mode ") {
            state.currentFile?.pendingOldMode = String(line.dropFirst("old mode ".count))
            return
        }
        if line.hasPrefix("new mode ") {
            state.currentFile?.pendingNewMode = String(line.dropFirst("new mode ".count))
            return
        }
        if line.hasPrefix("Binary files ") {
            state.currentFile?.status = .binary
            return
        }
        if line.hasPrefix("rename from ") {
            let from = String(line.dropFirst("rename from ".count))
            state.currentFile?.status = .renamed(from: from)
            return
        }
        if line.hasPrefix("rename to ") {
            let dest = String(line.dropFirst("rename to ".count))
            state.currentFile?.path = dest
            state.currentFile?.tokeniser = LanguageDetector.tokeniser(forPath: dest)
            return
        }
        if line.hasPrefix("copy from ") {
            let from = String(line.dropFirst("copy from ".count))
            state.currentFile?.status = .copied(from: from)
            return
        }
        if line.hasPrefix("copy to ") {
            let dest = String(line.dropFirst("copy to ".count))
            state.currentFile?.path = dest
            state.currentFile?.tokeniser = LanguageDetector.tokeniser(forPath: dest)
            return
        }
        if line.hasPrefix("similarity index ") || line.hasPrefix("dissimilarity index ") {
            return
        }
        if line.hasPrefix("--- ") {
            let path = String(line.dropFirst("--- ".count))
            if path == "/dev/null" {
                overrideToAddedOrDeleted(.added, state: &state)
            }
            return
        }
        if line.hasPrefix("+++ ") {
            let path = String(line.dropFirst("+++ ".count))
            if path == "/dev/null" {
                overrideToAddedOrDeleted(.deleted, state: &state)
            } else {
                adoptDestinationPath(path, state: &state)
            }
            return
        }
        // Unknown header lines are intentionally skipped (forgiving parse).
    }

    // `/dev/null` only resolves status when the file is still `.modified` and
    // no mode change has been seen. Explicit statuses (`.added`, `.deleted`,
    // `.submodule`, `.renamed`, `.copied`, `.binary`) and mode-change-only
    // states are never overwritten — that protects against the `.added ↔
    // .deleted` flip a malformed diff could otherwise force.
    private static func overrideToAddedOrDeleted(_ candidate: FileStatus, state: inout ParseState) {
        guard let current = state.currentFile?.status else { return }
        switch current {
        case .submodule, .renamed, .copied, .binary, .added, .deleted:
            return
        case .modified:
            guard state.currentFile?.pendingOldMode == nil,
                state.currentFile?.pendingNewMode == nil
            else { return }
            state.currentFile?.status = candidate
        }
    }

    // The `+++ b/<path>` line is git's authoritative destination path. Adopt it
    // unless a rename/copy header (which carries the same information) already
    // ran, or status is .deleted (no destination). Strip the `b/` prefix so the
    // result matches what extractPath produces.
    private static func adoptDestinationPath(_ raw: String, state: inout ParseState) {
        guard let current = state.currentFile?.status else { return }
        switch current {
        case .deleted, .renamed, .copied:
            return
        case .added, .modified, .submodule, .binary:
            var path = raw
            if path.hasPrefix("\"") { path.removeFirst() }
            if path.hasSuffix("\"") { path.removeLast() }
            if path.hasPrefix("b/") { path.removeFirst(2) }
            if path.isEmpty || path == state.currentFile?.path { return }
            state.currentFile?.path = path
            state.currentFile?.tokeniser = LanguageDetector.tokeniser(forPath: path)
        }
    }

    private static func handleIndexLine(_ line: String, state: inout ParseState) {
        let body = line.dropFirst("index ".count)
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let shas = parts[0].split(separator: "..", maxSplits: 1, omittingEmptySubsequences: false)
        guard shas.count == 2 else { return }
        let oldSha = String(shas[0])
        let newSha = String(shas[1])
        if parts.count == 2 {
            state.currentFile?.fileMode = String(parts[1])
        }
        if state.currentFile?.fileMode == "160000" {
            state.currentFile?.status = .submodule(from: oldSha, to: newSha)
        }
    }

    // MARK: - Hunk

    private static func startHunk(headerLine: String, state: inout ParseState) {
        guard let parsed = parseHunkHeader(headerLine) else {
            // Mark the malformed hunk and let parsing continue. Body lines that
            // follow are silently swallowed because `currentHunk` is nil. Prior
            // good hunks of this file are preserved.
            state.sawMalformedHunk = true
            state.lastBodyLineIndex = nil
            return
        }
        state.currentHunk = PartialHunk(
            oldStart: parsed.oldStart,
            oldCount: parsed.oldCount,
            newStart: parsed.newStart,
            newCount: parsed.newCount,
            headerContext: parsed.context
        )
        state.lastBodyLineIndex = nil
    }

    private struct ParsedHunkHeader {
        var oldStart: Int
        var oldCount: Int
        var newStart: Int
        var newCount: Int
        var context: String
    }

    private static func parseHunkHeader(_ line: String) -> ParsedHunkHeader? {
        guard let firstAt = line.range(of: "@@ "),
            let secondAt = line.range(of: " @@", range: firstAt.upperBound..<line.endIndex)
        else {
            return nil
        }
        let inside = line[firstAt.upperBound..<secondAt.lowerBound]
        var context = String(line[secondAt.upperBound..<line.endIndex])
        if context.hasPrefix(" ") { context.removeFirst() }

        let segments = inside.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard segments.count == 2,
            let old = parseRange(segments[0], expectedPrefix: "-"),
            let new = parseRange(segments[1], expectedPrefix: "+")
        else {
            return nil
        }
        return ParsedHunkHeader(
            oldStart: old.start,
            oldCount: old.count,
            newStart: new.start,
            newCount: new.count,
            context: context
        )
    }

    private static func parseRange(
        _ raw: Substring,
        expectedPrefix: Character
    ) -> (start: Int, count: Int)? {
        guard raw.first == expectedPrefix else { return nil }
        let body = raw.dropFirst()
        let parts = body.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let start = Int(parts[0]) else { return nil }
        let count: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else { return nil }
            count = parsed
        } else {
            count = 1
        }
        return (start, count)
    }

    // MARK: - Body line

    private static func appendBodyLine(_ line: String, state: inout ParseState) {
        guard state.currentHunk != nil else { return }
        guard let first = line.first else { return }

        if first == "\\" {
            markNoTrailingNewline(state: &state)
            return
        }

        let kind: LineKind
        switch first {
        case "+": kind = .added
        case "-": kind = .removed
        default: kind = .context
        }
        let content = String(line.dropFirst())
        appendLine(kind: kind, content: content, state: &state)
    }

    private static func appendContextLine(content: String, state: inout ParseState) {
        appendLine(kind: .context, content: content, state: &state)
    }

    private static func appendLine(kind: LineKind, content: String, state: inout ParseState) {
        let tokens = tokenise(content, with: state.currentFile?.tokeniser)
        let newLine = Line(kind: kind, content: content, tokens: tokens)
        state.currentHunk?.lines.append(newLine)
        state.lastBodyLineIndex = (state.currentHunk?.lines.count ?? 1) - 1
    }

    // Per-line tokenisation. Multi-line constructs (multi-line strings, nested
    // comments) are intentionally not stitched across diff lines — the start
    // state resets to `.tokenisingCode` per call. Acceptable for diff fragments;
    // documented in notes.md.
    private static func tokenise(
        _ content: String,
        with tokeniser: LanguageConfiguration.Tokeniser?
    ) -> [DiffToken] {
        guard let tokeniser, !content.isEmpty else { return [] }
        let raw = content.tokenise(with: tokeniser, state: LanguageConfiguration.State.tokenisingCode)
        return raw.compactMap { token in
            // Convert NSRange (UTF-16) back to Range<String.Index>. Drop the
            // token if the boundary falls inside a surrogate pair — safer than
            // returning a half-grapheme range that would crash on slice.
            guard let range = Range(token.range, in: content) else { return nil }
            return DiffToken(kind: token.token, range: range)
        }
    }

    private static func markNoTrailingNewline(state: inout ParseState) {
        guard var hunk = state.currentHunk,
            let idx = state.lastBodyLineIndex,
            idx < hunk.lines.count
        else {
            return
        }
        let existing = hunk.lines[idx]
        hunk.lines[idx] = Line(
            kind: existing.kind,
            content: existing.content,
            tokens: existing.tokens,
            hasNoTrailingNewline: true
        )
        state.currentHunk = hunk
    }

    // MARK: - Flush

    private static func flushHunk(state: inout ParseState) {
        guard let partial = state.currentHunk else { return }
        let hunk = Hunk(
            oldStart: partial.oldStart,
            oldCount: partial.oldCount,
            newStart: partial.newStart,
            newCount: partial.newCount,
            headerContext: partial.headerContext,
            lines: partial.lines
        )
        state.currentFile?.hunks.append(hunk)
        state.currentHunk = nil
        state.lastBodyLineIndex = nil
    }

    private static func flushFile(state: inout ParseState, files: inout [FileDiff]) {
        flushHunk(state: &state)
        defer {
            state.currentFile = nil
            state.sawMalformedHunk = false
        }
        guard var partial = state.currentFile else { return }

        // Drop the file when it has no surviving content (empty path is always
        // malformed; a malformed hunk without any prior good hunks leaves the
        // file empty too — there is nothing meaningful to expose).
        if partial.path.isEmpty { return }
        if state.sawMalformedHunk, partial.hunks.isEmpty { return }

        // Mode-change pair: emit only when both sides arrived. A single-sided
        // pair is dropped silently — the consumer never sees a half-formed
        // ModeChange.
        let modeChange: ModeChange?
        if let old = partial.pendingOldMode, let new = partial.pendingNewMode {
            modeChange = ModeChange(old: old, new: new)
        } else {
            modeChange = nil
        }

        // Contradictory state: binary/submodule diffs have no text hunks. Drop
        // any text hunks that snuck in so downstream renderers see a coherent
        // value.
        switch partial.status {
        case .binary, .submodule:
            partial.hunks = []
        case .added, .deleted, .modified, .renamed, .copied:
            break
        }

        files.append(
            FileDiff(
                path: partial.path,
                status: partial.status,
                modeChange: modeChange,
                hunks: partial.hunks
            )
        )
    }
}
