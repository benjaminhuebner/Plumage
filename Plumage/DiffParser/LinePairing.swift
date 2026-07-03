nonisolated public struct LinePair: Sendable, Equatable, Hashable {
    public let removed: Int
    public let added: Int

    public init(removed: Int, added: Int) {
        self.removed = removed
        self.added = added
    }
}

nonisolated public enum LinePairing {
    public static func pairs(in lines: [Line]) -> [LinePair] {
        var result: [LinePair] = []
        var index = 0
        while index < lines.count {
            guard lines[index].kind == .removed else {
                index += 1
                continue
            }
            let removedStart = index
            while index < lines.count, lines[index].kind == .removed { index += 1 }
            let addedStart = index
            while index < lines.count, lines[index].kind == .added { index += 1 }
            let pairCount = min(addedStart - removedStart, index - addedStart)
            for offset in 0..<pairCount {
                result.append(LinePair(removed: removedStart + offset, added: addedStart + offset))
            }
        }
        return result
    }
}
