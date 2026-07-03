nonisolated public struct SideBySideCell: Sendable, Equatable {
    public let line: Line
    public let number: Int

    public init(line: Line, number: Int) {
        self.line = line
        self.number = number
    }
}

nonisolated public struct SideBySideRow: Sendable, Equatable {
    public let old: SideBySideCell?
    public let new: SideBySideCell?

    public init(old: SideBySideCell?, new: SideBySideCell?) {
        self.old = old
        self.new = new
    }
}

nonisolated public enum SideBySideLayout {
    public static func rows(for hunk: Hunk) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var oldNumber = hunk.oldStart
        var newNumber = hunk.newStart
        let lines = hunk.lines
        var index = 0
        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .context:
                rows.append(
                    SideBySideRow(
                        old: SideBySideCell(line: line, number: oldNumber),
                        new: SideBySideCell(line: line, number: newNumber)
                    )
                )
                oldNumber += 1
                newNumber += 1
                index += 1
            case .added:
                rows.append(
                    SideBySideRow(old: nil, new: SideBySideCell(line: line, number: newNumber))
                )
                newNumber += 1
                index += 1
            case .removed:
                let removedStart = index
                while index < lines.count, lines[index].kind == .removed { index += 1 }
                let addedStart = index
                while index < lines.count, lines[index].kind == .added { index += 1 }
                let removedCount = addedStart - removedStart
                let addedCount = index - addedStart
                for offset in 0..<max(removedCount, addedCount) {
                    var old: SideBySideCell?
                    var new: SideBySideCell?
                    if offset < removedCount {
                        old = SideBySideCell(line: lines[removedStart + offset], number: oldNumber)
                        oldNumber += 1
                    }
                    if offset < addedCount {
                        new = SideBySideCell(line: lines[addedStart + offset], number: newNumber)
                        newNumber += 1
                    }
                    rows.append(SideBySideRow(old: old, new: new))
                }
            }
        }
        return rows
    }

    public static func columnDigits(for hunk: Hunk) -> (old: Int, new: Int) {
        let maxOld = max(hunk.oldStart + max(hunk.oldCount, 1) - 1, 1)
        let maxNew = max(hunk.newStart + max(hunk.newCount, 1) - 1, 1)
        return (String(maxOld).count, String(maxNew).count)
    }
}
