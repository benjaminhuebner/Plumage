import Foundation

nonisolated enum TextOffset {
    static func offset(ofLine line: Int, column: Int, in text: String) -> Int {
        let safeLine = max(1, line)
        let safeColumn = max(1, column)
        var currentLine = 1
        var index = text.startIndex
        while index < text.endIndex && currentLine < safeLine {
            if text[index] == "\n" {
                currentLine += 1
            }
            index = text.index(after: index)
        }
        var columnIndex = 1
        while index < text.endIndex && columnIndex < safeColumn && text[index] != "\n" {
            index = text.index(after: index)
            columnIndex += 1
        }
        return text.utf16.distance(
            from: text.utf16.startIndex, to: index.samePosition(in: text.utf16) ?? text.utf16.endIndex)
    }
}
