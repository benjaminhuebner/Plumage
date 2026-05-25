import Foundation
import LanguageSupport

nonisolated public enum DiffParser {
    public static func parse(unifiedDiff: String) -> [FileDiff] {
        var input = unifiedDiff
        if input.hasPrefix("\u{FEFF}") { input.removeFirst() }
        input = input.replacingOccurrences(of: "\r\n", with: "\n")
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
        var droppedCurrentFile = false
    }

    private struct PartialFileDiff {
        var path: String
        var status: FileStatus = .modified
        var modeChange: ModeChange?
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
        if state.droppedCurrentFile { return }

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
        state.droppedCurrentFile = false
    }

    private static func extractPath(fromDiffGitHeader header: String) -> String {
        let trimmed = header.dropFirst("diff --git ".count)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let bSide = parts.last else { return "" }
        var path = String(bSide)
        if path.hasPrefix("b/") { path.removeFirst(2) }
        return path
    }

    // MARK: - Header (non-body, non-hunk)

    private static func handleHeaderLine(_ line: String, state: inout ParseState) {
        if line.hasPrefix("new file mode ") {
            state.currentFile?.status = .added
            return
        }
        if line.hasPrefix("deleted file mode ") {
            state.currentFile?.status = .deleted
            return
        }
        if line.hasPrefix("old mode ") {
            let mode = String(line.dropFirst("old mode ".count))
            let existingNew = state.currentFile?.modeChange?.new ?? ""
            state.currentFile?.modeChange = ModeChange(old: mode, new: existingNew)
            return
        }
        if line.hasPrefix("new mode ") {
            let mode = String(line.dropFirst("new mode ".count))
            let existingOld = state.currentFile?.modeChange?.old ?? ""
            state.currentFile?.modeChange = ModeChange(old: existingOld, new: mode)
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
            let to = String(line.dropFirst("rename to ".count))
            state.currentFile?.path = to
            state.currentFile?.tokeniser = LanguageDetector.tokeniser(forPath: to)
            return
        }
        if line.hasPrefix("copy from ") {
            let from = String(line.dropFirst("copy from ".count))
            state.currentFile?.status = .copied(from: from)
            return
        }
        if line.hasPrefix("copy to ") {
            let to = String(line.dropFirst("copy to ".count))
            state.currentFile?.path = to
            state.currentFile?.tokeniser = LanguageDetector.tokeniser(forPath: to)
            return
        }
        if line.hasPrefix("similarity index ") || line.hasPrefix("dissimilarity index ") {
            return
        }
        if line.hasPrefix("--- ") {
            let path = String(line.dropFirst("--- ".count))
            if path == "/dev/null" {
                state.currentFile?.status = .added
            }
            return
        }
        if line.hasPrefix("+++ ") {
            let path = String(line.dropFirst("+++ ".count))
            if path == "/dev/null" {
                state.currentFile?.status = .deleted
            }
            return
        }
        // Unknown header lines are intentionally skipped (forgiving parse).
    }

    // MARK: - Hunk

    private static func startHunk(headerLine: String, state: inout ParseState) {
        guard let parsed = parseHunkHeader(headerLine) else {
            state.droppedCurrentFile = true
            state.currentFile = nil
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
        return raw.map { DiffToken(kind: $0.token, range: $0.range) }
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
        if state.droppedCurrentFile {
            state.currentFile = nil
            state.droppedCurrentFile = false
            return
        }
        guard let partial = state.currentFile else { return }
        files.append(
            FileDiff(
                path: partial.path,
                status: partial.status,
                modeChange: partial.modeChange,
                hunks: partial.hunks
            ))
        state.currentFile = nil
    }
}
