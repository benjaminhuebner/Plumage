import Foundation

nonisolated enum TextOffset {
    // Returns a UTF-16 offset (NSRange-compatible) for the given 1-based
    // line/column. Scans UTF-16 directly so there's no risk of landing on
    // an index that can't round-trip through `String.Index.samePosition(in:)`
    // — surrogate-pair edges fall through cleanly.
    static func offset(ofLine line: Int, column: Int, in text: String) -> Int {
        let safeLine = max(1, line)
        let safeColumn = max(1, column)
        let utf16 = text.utf16
        let newline: UTF16.CodeUnit = 0x0A
        var index = utf16.startIndex
        var currentLine = 1
        while index < utf16.endIndex && currentLine < safeLine {
            if utf16[index] == newline { currentLine += 1 }
            index = utf16.index(after: index)
        }
        var columnIndex = 1
        while index < utf16.endIndex && columnIndex < safeColumn && utf16[index] != newline {
            index = utf16.index(after: index)
            columnIndex += 1
        }
        return utf16.distance(from: utf16.startIndex, to: index)
    }
}
