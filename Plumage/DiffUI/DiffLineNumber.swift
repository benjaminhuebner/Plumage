import Foundation

nonisolated struct DiffLineNumber: Equatable, Sendable {
    let old: Int?
    let new: Int?

    static func numbers(for hunk: Hunk) -> [DiffLineNumber] {
        var oldNumber = hunk.oldStart
        var newNumber = hunk.newStart
        var result: [DiffLineNumber] = []
        result.reserveCapacity(hunk.lines.count)
        for line in hunk.lines {
            switch line.kind {
            case .added:
                result.append(DiffLineNumber(old: nil, new: newNumber))
                newNumber += 1
            case .removed:
                result.append(DiffLineNumber(old: oldNumber, new: nil))
                oldNumber += 1
            case .context:
                result.append(DiffLineNumber(old: oldNumber, new: newNumber))
                oldNumber += 1
                newNumber += 1
            }
        }
        return result
    }

    static func columnDigits(for hunk: Hunk) -> Int {
        let highest = max(hunk.oldStart + hunk.oldCount, hunk.newStart + hunk.newCount)
        return String(max(highest, 1)).count
    }
}
